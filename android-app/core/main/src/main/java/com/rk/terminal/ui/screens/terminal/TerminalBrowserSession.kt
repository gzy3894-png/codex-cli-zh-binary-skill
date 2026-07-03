package com.rk.terminal.ui.screens.terminal

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.resume

data class TerminalBrowserTabSnapshot(
    val id: Int,
    val title: String,
    val url: String,
    val isLoading: Boolean
)

data class TerminalBrowserSnapshot(
    val available: Boolean = false,
    val activeTabId: Int? = null,
    val title: String = "",
    val currentUrl: String = "",
    val isLoading: Boolean = false,
    val status: String = "idle",
    val message: String = "",
    val needsUser: Boolean = false,
    val lastError: String? = null,
    val tabs: List<TerminalBrowserTabSnapshot> = emptyList()
)

private data class BrowserTab(
    val id: Int,
    val contextWrapper: MutableContextWrapper,
    val webView: WebView,
    var title: String = "Blank",
    var currentUrl: String = "about:blank",
    var isLoading: Boolean = false,
    var lastError: String? = null,
    var loadWaiter: CompletableDeferred<Unit>? = null
)

class TerminalBrowserSessionManager(
    context: Context,
    private val onSnapshot: (TerminalBrowserSnapshot) -> Unit
) {
    private val appContext = context.applicationContext
    private val tabs = linkedMapOf<Int, BrowserTab>()
    private var nextTabId = 0
    private var activeTabId: Int? = null
    private var attachedContainer: ViewGroup? = null
    private var latestSnapshot = TerminalBrowserSnapshot()
    private var needsUser = false
    private var userMessage = ""

    fun snapshot(): TerminalBrowserSnapshot = latestSnapshot

    suspend fun handleRequest(
        request: Map<String, String>,
        browserDir: File
    ): JSONObject = withContext(Dispatchers.Main.immediate) {
        val action = request["action"]?.trim().orEmpty().ifBlank { "snapshot" }
        val requestId = request["request_id"] ?: request["stamp"] ?: System.currentTimeMillis().toString()
        val result = runCatching {
            when (action) {
                "open", "navigate" -> navigate(request.requireValue("url"))
                "reload" -> {
                    activeTab().webView.reload()
                    publish("running", "刷新中")
                    JSONObject().put("reloading", true)
                }
                "back", "go_back" -> goBack()
                "forward", "go_forward" -> goForward()
                "new_tab" -> newTab(request["url"])
                "select_tab" -> selectTab(request.requireValue("tab_id").toInt())
                "close_tab" -> closeTab(request["tab_id"]?.toIntOrNull())
                "click" -> click(request)
                "type" -> type(request)
                "scroll" -> scroll(request)
                "get_text" -> getText(request["selector"])
                "get_readable" -> getReadable()
                "execute_js", "js" -> executeJs(request.requireValue("script"))
                "screenshot" -> screenshot(browserDir, requestId)
                "user_wait" -> userWait(request["message"].orEmpty().ifBlank { "请在浏览器中手动处理后继续" })
                "user_done" -> userDone()
                "close" -> closeSession()
                "snapshot" -> JSONObject()
                else -> throw IllegalArgumentException("unsupported action: $action")
            }
        }
        val ok = result.isSuccess
        if (!ok) {
            publish("error", result.exceptionOrNull()?.message.orEmpty())
        } else if (action !in setOf("open", "navigate", "reload", "user_wait", "close")) {
            publish("done", action)
        }
        JSONObject()
            .put("ok", ok)
            .put("requestId", requestId)
            .put("action", action)
            .put("error", result.exceptionOrNull()?.message)
            .put("data", result.getOrNull() ?: JSONObject())
            .put("snapshot", snapshotJson(snapshot()))
    }

    fun attachTo(container: FrameLayout) {
        attachedContainer = container
        val tab = tabs[activeTabId] ?: tabs.values.lastOrNull() ?: return
        activeTabId = tab.id
        tab.contextWrapper.baseContext = container.context
        val currentParent = tab.webView.parent as? ViewGroup
        if (currentParent !== container) {
            currentParent?.removeView(tab.webView)
            container.removeAllViews()
            container.addView(
                tab.webView,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }
        layoutWebView(tab.webView)
    }

    fun detachFrom(container: FrameLayout) {
        if (attachedContainer !== container) return
        val tab = tabs[activeTabId] ?: tabs.values.lastOrNull() ?: return
        val parent = tab.webView.parent as? ViewGroup
        if (parent === container) {
            parent.removeView(tab.webView)
        }
        tab.contextWrapper.baseContext = appContext
        attachedContainer = null
    }

    fun closeSession(): JSONObject {
        tabs.values.forEach { tab ->
            runCatching {
                (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
                tab.webView.stopLoading()
                tab.webView.destroy()
            }
        }
        tabs.clear()
        activeTabId = null
        attachedContainer = null
        needsUser = false
        userMessage = ""
        publish("closed", "浏览器已关闭")
        return JSONObject().put("closed", true)
    }

    private suspend fun navigate(rawUrl: String): JSONObject {
        val tab = tabs[activeTabId] ?: createTab()
        val url = normalizeUrl(rawUrl)
        activeTabId = tab.id
        tab.loadWaiter = CompletableDeferred()
        tab.currentUrl = url
        tab.lastError = null
        tab.isLoading = true
        needsUser = false
        userMessage = ""
        publish("running", "打开网页")
        tab.webView.loadUrl(url)
        withTimeoutOrNull(15000) {
            tab.loadWaiter?.await()
        }
        publish("done", "网页已打开")
        return JSONObject()
            .put("tabId", tab.id)
            .put("url", tab.currentUrl)
            .put("title", tab.title)
    }

    private fun goBack(): JSONObject {
        val webView = activeTab().webView
        if (webView.canGoBack()) webView.goBack()
        return JSONObject().put("canGoBack", webView.canGoBack())
    }

    private fun goForward(): JSONObject {
        val webView = activeTab().webView
        if (webView.canGoForward()) webView.goForward()
        return JSONObject().put("canGoForward", webView.canGoForward())
    }

    private suspend fun newTab(url: String?): JSONObject {
        val tab = createTab()
        activeTabId = tab.id
        publish("done", "新标签页")
        if (!url.isNullOrBlank()) {
            navigate(url)
        }
        return JSONObject().put("tabId", tab.id)
    }

    private fun selectTab(tabId: Int): JSONObject {
        require(tabs.containsKey(tabId)) { "tab not found: $tabId" }
        activeTabId = tabId
        attachedContainer?.let { attachTo(it as FrameLayout) }
        publish("done", "已切换标签页")
        return JSONObject().put("tabId", tabId)
    }

    private fun closeTab(tabId: Int?): JSONObject {
        val id = tabId ?: activeTabId ?: return JSONObject().put("closed", false)
        val tab = tabs.remove(id) ?: return JSONObject().put("closed", false)
        (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
        tab.webView.stopLoading()
        tab.webView.destroy()
        if (activeTabId == id) {
            activeTabId = tabs.keys.lastOrNull()
        }
        attachedContainer?.let { attachTo(it as FrameLayout) }
        publish("done", "已关闭标签页")
        return JSONObject().put("closed", true).put("tabId", id)
    }

    private suspend fun click(request: Map<String, String>): JSONObject {
        val selector = request["selector"]
        val x = request["x"]?.toIntOrNull()
        val y = request["y"]?.toIntOrNull()
        val script = if (!selector.isNullOrBlank()) {
            """
            const target = document.querySelector(${JSONObject.quote(selector)});
            if (!target) throw new Error('Element not found: ${selector.replace("'", "")}');
            target.scrollIntoView({block:'center', inline:'center'});
            target.click();
            return {selector:${JSONObject.quote(selector)}, text:(target.innerText||target.value||target.getAttribute('aria-label')||'').slice(0,200)};
            """.trimIndent()
        } else {
            require(x != null && y != null) { "click needs selector or x/y" }
            """
            const target = document.elementFromPoint($x, $y);
            if (!target) throw new Error('No element at coordinate');
            target.click();
            return {x:$x,y:$y,text:(target.innerText||target.value||target.getAttribute('aria-label')||'').slice(0,200)};
            """.trimIndent()
        }
        val result = evalObject(script)
        delay(350)
        return result
    }

    private suspend fun type(request: Map<String, String>): JSONObject {
        val selector = request.requireValue("selector")
        val text = request["text"].orEmpty()
        val script = """
            const target = document.querySelector(${JSONObject.quote(selector)});
            if (!target) throw new Error('Element not found: ${selector.replace("'", "")}');
            target.focus();
            target.value = ${JSONObject.quote(text)};
            target.dispatchEvent(new Event('input', {bubbles:true}));
            target.dispatchEvent(new Event('change', {bubbles:true}));
            return {selector:${JSONObject.quote(selector)}, textLength:${text.length}};
        """.trimIndent()
        return evalObject(script)
    }

    private suspend fun scroll(request: Map<String, String>): JSONObject {
        val direction = request["direction"] ?: "down"
        val amount = request["amount"]?.toIntOrNull()?.coerceIn(1, 20000) ?: 600
        val signed = if (direction == "up") -amount else amount
        val script = """
            const before = window.scrollY || document.documentElement.scrollTop || 0;
            window.scrollBy(0, $signed);
            const after = window.scrollY || document.documentElement.scrollTop || 0;
            return {direction:${JSONObject.quote(direction)}, amount:$amount, before:before, after:after};
        """.trimIndent()
        val result = evalObject(script)
        delay(250)
        return result
    }

    private suspend fun getText(selector: String?): JSONObject {
        val selectorLiteral = selector?.let { JSONObject.quote(it) } ?: "null"
        return evalObject(
            """
            const selector = $selectorLiteral;
            const target = selector ? document.querySelector(selector) : document.body;
            if (!target) throw new Error('Element not found: ' + selector);
            const text = (target.innerText || target.textContent || '').replace(/\s+/g, ' ').trim();
            return {selector:selector, text:text, textLength:text.length};
            """.trimIndent()
        )
    }

    private suspend fun getReadable(): JSONObject = getText("main, article, [role='main'], body")

    private suspend fun executeJs(script: String): JSONObject = evalObject(
        """
        const value = (function(){ ${script} })();
        return {value: String(value === undefined ? '' : value).slice(0, 4000)};
        """.trimIndent()
    )

    private suspend fun screenshot(browserDir: File, requestId: String): JSONObject {
        val tab = activeTab()
        val file = File(browserDir, "screenshots/$requestId.png")
        val bytesWritten = withContext(Dispatchers.Main.immediate) {
            val (width, height) = layoutWebView(tab.webView)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            tab.webView.draw(canvas)
            withContext(Dispatchers.IO) {
                file.parentFile?.mkdirs()
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                file.length()
            }.also {
                bitmap.recycle()
            }
        }
        return JSONObject()
            .put("path", file.absolutePath)
            .put("bytes", bytesWritten)
    }

    private fun userWait(message: String): JSONObject {
        needsUser = true
        userMessage = message
        publish("waiting_for_user", message)
        return JSONObject().put("message", message)
    }

    private fun userDone(): JSONObject {
        needsUser = false
        userMessage = ""
        publish("done", "用户已完成接管")
        return JSONObject().put("userDone", true)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createTab(): BrowserTab {
        require(tabs.size < MAX_BROWSER_TABS) { "browser tab limit is $MAX_BROWSER_TABS" }
        val tabId = ++nextTabId
        val contextWrapper = MutableContextWrapper(appContext)
        val webView = WebView(contextWrapper).apply {
            setBackgroundColor(Color.WHITE)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            settings.setSupportZoom(true)
            settings.builtInZoomControls = true
            settings.displayZoomControls = false
            settings.mediaPlaybackRequiresUserGesture = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settings.safeBrowsingEnabled = true
            }
        }
        val tab = BrowserTab(id = tabId, contextWrapper = contextWrapper, webView = webView)
        webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView?, title: String?) {
                tab.title = title.orEmpty().ifBlank { tab.currentUrl }
                publish()
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                tab.currentUrl = url.orEmpty()
                tab.isLoading = true
                publish("running", "加载中")
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                tab.currentUrl = url.orEmpty().ifBlank { tab.currentUrl }
                tab.title = view?.title.orEmpty().ifBlank { tab.currentUrl }
                tab.isLoading = false
                tab.loadWaiter?.complete(Unit)
                tab.loadWaiter = null
                publish("done", "网页已加载")
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request?.isForMainFrame != false) {
                    tab.lastError = error?.description?.toString()
                    tab.isLoading = false
                    tab.loadWaiter?.complete(Unit)
                    publish("error", tab.lastError.orEmpty())
                }
            }
        }
        tabs[tabId] = tab
        activeTabId = tabId
        publish("done", "浏览器已创建")
        return tab
    }

    private fun activeTab(): BrowserTab {
        return tabs[activeTabId] ?: tabs.values.lastOrNull() ?: createTab()
    }

    private suspend fun evalObject(command: String): JSONObject {
        val wrapped = """
            (function(){
              try {
                const result = (function(){ $command })();
                return JSON.stringify({ok:true, result:result});
              } catch (error) {
                return JSON.stringify({ok:false, error:String(error && error.message ? error.message : error)});
              }
            })();
        """.trimIndent()
        val raw = activeTab().webView.evaluate(wrapped)
        val decoded = decodeJsString(raw)
        val envelope = JSONObject(decoded)
        if (!envelope.optBoolean("ok")) {
            throw IllegalStateException(envelope.optString("error", "browser js failed"))
        }
        return envelope.optJSONObject("result") ?: JSONObject().put("value", envelope.opt("result"))
    }

    private fun publish(
        status: String = latestSnapshot.status,
        message: String = latestSnapshot.message
    ) {
        val active = activeTabId?.let { tabs[it] }
        latestSnapshot = TerminalBrowserSnapshot(
            available = tabs.isNotEmpty(),
            activeTabId = active?.id,
            title = active?.title.orEmpty(),
            currentUrl = active?.currentUrl.orEmpty(),
            isLoading = active?.isLoading == true,
            status = if (needsUser) "waiting_for_user" else status,
            message = if (needsUser) userMessage else message,
            needsUser = needsUser,
            lastError = active?.lastError,
            tabs = tabs.values.map {
                TerminalBrowserTabSnapshot(
                    id = it.id,
                    title = it.title,
                    url = it.currentUrl,
                    isLoading = it.isLoading
                )
            }
        )
        onSnapshot(latestSnapshot)
    }

    private fun layoutWebView(webView: WebView): Pair<Int, Int> {
        val display = appContext.resources.displayMetrics
        val parent = webView.parent as? View
        val width = listOf(webView.width, webView.measuredWidth, parent?.width ?: 0, display.widthPixels)
            .firstOrNull { it > 0 } ?: 1080
        val height = listOf(webView.height, webView.measuredHeight, parent?.height ?: 0, display.heightPixels)
            .firstOrNull { it > 0 } ?: 1920
        val widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        webView.measure(widthSpec, heightSpec)
        webView.layout(0, 0, width, height)
        return width to height
    }

    private suspend fun WebView.evaluate(script: String): String? =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { value ->
                if (continuation.isActive) {
                    continuation.resume(value)
                }
            }
        }

    private fun snapshotJson(snapshot: TerminalBrowserSnapshot): JSONObject {
        return JSONObject()
            .put("available", snapshot.available)
            .put("activeTabId", snapshot.activeTabId)
            .put("title", snapshot.title)
            .put("currentUrl", snapshot.currentUrl)
            .put("isLoading", snapshot.isLoading)
            .put("status", snapshot.status)
            .put("message", snapshot.message)
            .put("needsUser", snapshot.needsUser)
            .put("lastError", snapshot.lastError)
            .put("tabs", JSONArray().apply {
                snapshot.tabs.forEach { tab ->
                    put(
                        JSONObject()
                            .put("id", tab.id)
                            .put("title", tab.title)
                            .put("url", tab.url)
                            .put("isLoading", tab.isLoading)
                    )
                }
            })
    }

    private fun normalizeUrl(raw: String): String {
        val trimmed = raw.trim()
        require(trimmed.isNotEmpty()) { "url is empty" }
        return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "https://$trimmed"
        }
    }

    private fun decodeJsString(raw: String?): String {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return "{}"
        return try {
            when (val parsed = JSONTokener(text).nextValue()) {
                is String -> parsed
                else -> parsed.toString()
            }
        } catch (_: Exception) {
            text
        }
    }

    private fun Map<String, String>.requireValue(key: String): String {
        return this[key]?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("$key is required")
    }
}

private const val MAX_BROWSER_TABS = 3
