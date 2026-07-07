package com.rk.terminal.ui.screens.terminal

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.EditText
import androidx.browser.customtabs.CustomTabsIntent
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
import java.util.UUID
import kotlin.coroutines.resume

data class TerminalBrowserTabSnapshot(
    val id: Int,
    val title: String,
    val url: String,
    val isLoading: Boolean
)

data class TerminalBrowserAuthSnapshot(
    val requestId: String,
    val url: String,
    val reason: String,
    val code: String,
    val state: String,
    val userAction: String,
    val active: Boolean
)

data class TerminalBrowserExternalPromptSnapshot(
    val requestId: String,
    val target: String,
    val scheme: String,
    val fallbackUrl: String,
    val kind: String = "external"
)

data class TerminalBrowserSnapshot(
    val available: Boolean = false,
    val requestId: String = "",
    val activeTabId: Int? = null,
    val title: String = "",
    val currentUrl: String = "",
    val isLoading: Boolean = false,
    val status: String = "idle",
    val message: String = "",
    val needsUser: Boolean = false,
    val lastError: String? = null,
    val tabs: List<TerminalBrowserTabSnapshot> = emptyList(),
    val authTask: TerminalBrowserAuthSnapshot? = null,
    val externalPrompt: TerminalBrowserExternalPromptSnapshot? = null,
    val riskChallengeDetected: Boolean = false,
    val riskChallengeKind: String = "",
    val recommendedNextAction: String = ""
)

@SuppressLint("ViewConstructor")
private class CapturableWebView(context: Context) : WebView(context) {
    fun drawWebContent(canvas: Canvas) {
        super.onDraw(canvas)
    }
}

private data class BrowserTab(
    val id: Int,
    val contextWrapper: MutableContextWrapper,
    val webView: WebView,
    var title: String = "Blank",
    var currentUrl: String = "about:blank",
    var isLoading: Boolean = false,
    var lastError: String? = null,
    var loadWaiter: CompletableDeferred<Unit>? = null,
    var loadWaiterToken: Long = 0L,
    var loadStartedToken: Long = 0L,
    var loadingMainFrameUrl: String = "",
    var riskChallengeDetected: Boolean = false,
    var riskChallengeKind: String = "",
    var recommendedNextAction: String = ""
)

private data class BrowserPageTextSnapshot(
    val title: String,
    val url: String,
    val text: String
)

private data class BrowserUserScript(
    val id: String,
    val name: String,
    val match: String,
    val path: String,
    val enabled: Boolean
)

private data class BrowserAuthTask(
    val requestId: String,
    val url: String,
    val reason: String,
    val code: String,
    var state: String = "waiting_for_user",
    var userAction: String = "opened",
    var active: Boolean = true
)

private data class BrowserExternalOpenPrompt(
    val requestId: String,
    val target: String,
    val scheme: String,
    val fallbackUrl: String,
    val intent: Intent?,
    val kind: String = "external"
)

class TerminalBrowserSessionManager(
    context: Context,
    private val onSnapshot: (TerminalBrowserSnapshot) -> Unit,
    private val launchFileChooser: ((Intent, (Array<Uri>?) -> Unit) -> Unit)? = null
) {
    private val initialContext = context
    private val appContext = context.applicationContext
    private val tabs = linkedMapOf<Int, BrowserTab>()
    private var nextTabId = 0
    private var activeTabId: Int? = null
    private var attachedContainer: ViewGroup? = null
    private var latestSnapshot = TerminalBrowserSnapshot()
    private var needsUser = false
    private var userMessage = ""
    private var currentRequestId = ""
    private var activeUserRequestId = ""
    private var authTask: BrowserAuthTask? = null
    private var externalOpenPrompt: BrowserExternalOpenPrompt? = null
    private var currentBrowserDir: File? = null

    fun snapshot(): TerminalBrowserSnapshot = latestSnapshot

    fun hostWebView(context: Context): WebView {
        val tab = tabs[activeTabId] ?: tabs.values.lastOrNull() ?: createTab()
        activeTabId = tab.id
        tab.contextWrapper.baseContext = context
        (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
        tab.webView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        resumeHostedWebView(tab.webView)
        return tab.webView
    }

    fun updateHostedWebView(webView: WebView) {
        resumeHostedWebView(webView)
    }

    fun releaseHostedWebView(webView: WebView) {
        tabs.values.firstOrNull { it.webView === webView }?.contextWrapper?.baseContext = appContext
    }

    fun releaseHostedTab(tabId: Int?) {
        val tab = tabId?.let { tabs[it] } ?: activeTabId?.let { tabs[it] }
        tab?.contextWrapper?.baseContext = appContext
    }

    fun selectTabFromUi(tabId: Int) {
        runCatching { selectTab(tabId) }
    }

    fun closeTabFromUi(tabId: Int) {
        runCatching { closeTab(tabId) }
    }

    suspend fun handleRequest(
        request: Map<String, String>,
        browserDir: File
    ): JSONObject = withContext(Dispatchers.Main.immediate) {
        currentBrowserDir = browserDir
        val action = request["action"]?.trim().orEmpty().ifBlank { "snapshot" }
        val requestId = when (action) {
            "auth_done", "auth_cancel", "auth_cancelled", "auth_collapse", "auth_reopen" ->
                request["auth_request_id"]?.takeIf { it.isNotBlank() }
            "external_confirm", "external_cancel" ->
                request["external_request_id"]?.takeIf { it.isNotBlank() }
            else -> null
        } ?: request["request_id"] ?: request["stamp"] ?: System.currentTimeMillis().toString()
        currentRequestId = requestId
        clearCompletedUserTasksForPageAction(action)
        val result = runCatching {
            when (action) {
                "open", "navigate" -> navigate(request.requireValue("url"))
                "list_tabs" -> listTabs()
                "history" -> history(browserDir)
                "clear_history" -> clearHistory(browserDir)
                "cookies_status" -> cookieStatus(request["url"] ?: activeTab().currentUrl)
                "cookies_verify" -> cookieVerify(request["url"] ?: activeTab().currentUrl)
                "cookies_flush" -> cookieFlush()
                "userscript_add" -> userScriptAdd(browserDir, request)
                "userscript_list" -> userScriptList(browserDir)
                "userscript_enable" -> userScriptSetEnabled(browserDir, request.requireValue("id"), enabled = true)
                "userscript_disable" -> userScriptSetEnabled(browserDir, request.requireValue("id"), enabled = false)
                "userscript_remove" -> userScriptRemove(browserDir, request.requireValue("id"))
                "present" -> present(request["reason"].orEmpty().ifBlank { "present" })
                "collapse" -> JSONObject().put("collapsed", true)
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
                "screenshot" -> screenshot(browserDir, requestId, request)
                "external", "auth", "custom_tab", "auth_open" -> openAuthBrowser(request, requestId, action)
                "auth_reopen" -> reopenAuthBrowser(request, requestId)
                "auth_done" -> authDone(request["auth_request_id"] ?: requestId)
                "auth_cancel", "auth_cancelled" -> authCancelled(request["auth_request_id"] ?: requestId)
                "auth_collapse" -> authCollapsed(request["auth_request_id"] ?: requestId)
                "external_confirm" -> confirmExternalOpen(request["external_request_id"] ?: requestId)
                "external_cancel" -> cancelExternalOpen(request["external_request_id"] ?: requestId)
                "user_wait" -> userWait(
                    message = request["message"].orEmpty().ifBlank { "请在浏览器中手动处理后继续" },
                    requestId = requestId
                )
                "user_done" -> userDone()
                "user_collapse" -> userCollapse()
                "user_cancelled" -> userCancelled()
                "close" -> closeSession()
                "snapshot" -> JSONObject()
                else -> throw IllegalArgumentException("unsupported action: $action")
            }
        }
        val ok = result.isSuccess
        if (!ok) {
            publish("error", result.exceptionOrNull()?.message.orEmpty())
        } else if (action !in setOf(
                "open",
                "navigate",
                "reload",
                "user_wait",
                "user_done",
                "user_collapse",
                "user_cancelled",
                "present",
                "close",
                "auth_open",
                "auth_reopen",
                "auth_done",
                "auth_cancel",
                "auth_cancelled",
                "auth_collapse",
                "external_confirm",
                "external_cancel"
            )
        ) {
            publish("done", action)
        }
        cookieFlush()
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
        focusWebView(tab.webView)
        tab.webView.onResume()
        tab.webView.resumeTimers()
        tab.webView.requestLayout()
        tab.webView.post {
            layoutWebViewInContainer(tab.webView, container)
            tab.webView.requestLayout()
            tab.webView.invalidate()
        }
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
        activeUserRequestId = ""
        authTask = null
        externalOpenPrompt = null
        publish("closed", "浏览器已关闭")
        return JSONObject().put("closed", true)
    }

    private fun present(reason: String): JSONObject {
        publish("ready", reason)
        return JSONObject().put("presented", true).put("reason", reason)
    }

    private suspend fun navigate(rawUrl: String): JSONObject {
        val tab = tabs[activeTabId] ?: createTab()
        val url = normalizeUrl(rawUrl)
        activeTabId = tab.id
        val alreadyLoaded = tab.currentUrl.isNotBlank() &&
            urlsSameForLoad(url, tab.currentUrl) &&
            !tab.isLoading
        tab.currentUrl = url
        tab.lastError = null
        tab.riskChallengeDetected = false
        tab.riskChallengeKind = ""
        tab.recommendedNextAction = ""
        needsUser = false
        userMessage = ""
        externalOpenPrompt = null
        if (alreadyLoaded) {
            tab.title = tab.webView.title.orEmpty().ifBlank { tab.title.ifBlank { tab.currentUrl } }
            tab.isLoading = false
            cookieFlush()
            appendHistory(tab)
            publish("done", "网页已打开")
            return JSONObject()
                .put("tabId", tab.id)
                .put("url", redactSensitiveUrl(tab.currentUrl))
                .put("title", tab.title)
        }
        val loadToken = tab.loadWaiterToken + 1L
        val waiter = CompletableDeferred<Unit>()
        tab.loadWaiterToken = loadToken
        tab.loadStartedToken = 0L
        tab.loadingMainFrameUrl = url
        tab.loadWaiter = waiter
        tab.isLoading = true
        publish("running", "打开网页")
        waitForHostLayout(tab)
        tab.webView.loadUrl(url)
        val loaded = withTimeoutOrNull(20000) {
            waiter.await()
        } != null
        if (!loaded) {
            if (tab.loadWaiter === waiter && tab.loadWaiterToken == loadToken) {
                tab.loadWaiter = null
                tab.loadStartedToken = 0L
                tab.loadingMainFrameUrl = ""
                tab.isLoading = false
                tab.lastError = "Page load timed out"
                publish("error", tab.lastError.orEmpty())
            }
            throw IllegalStateException(tab.lastError ?: "Page load timed out or was superseded by another navigation")
        }
        tab.lastError?.takeIf { !it.startsWith("userscript", ignoreCase = true) }?.let {
            publish("error", it)
            throw IllegalStateException(it)
        }
        publish("done", "网页已打开")
        return JSONObject()
            .put("tabId", tab.id)
            .put("url", redactSensitiveUrl(tab.currentUrl))
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

    private fun listTabs(): JSONObject {
        return JSONObject()
            .put("activeTabId", activeTabId)
            .put("tabs", JSONArray().apply {
                tabs.values.forEach { tab ->
                    put(
                        JSONObject()
                            .put("id", tab.id)
                            .put("title", tab.title)
                            .put("url", redactSensitiveUrl(tab.currentUrl))
                            .put("isLoading", tab.isLoading)
                            .put("canGoBack", tab.webView.canGoBack())
                            .put("canGoForward", tab.webView.canGoForward())
                    )
                }
            })
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

    private fun history(browserDir: File): JSONObject {
        val entries = JSONArray()
        val historyFile = File(browserDir, "history.jsonl")
        if (historyFile.isFile) {
            historyFile.readLines().takeLast(200).forEach { line ->
                runCatching { JSONObject(line) }.getOrNull()?.let {
                    entries.put(it.put("url", redactSensitiveUrl(it.optString("url"))))
                }
            }
        }
        return JSONObject().put("entries", entries).put("count", entries.length())
    }

    private fun clearHistory(browserDir: File): JSONObject {
        File(browserDir, "history.jsonl").delete()
        return JSONObject().put("cleared", true)
    }

    private fun cookieStatus(rawUrl: String): JSONObject {
        val url = normalizeCookieUrl(rawUrl.takeIf { it.isNotBlank() } ?: activeTab().currentUrl)
        val rawCookie = CookieManager.getInstance().getCookie(url).orEmpty()
        val names = rawCookie.split(';')
            .map { it.trim().substringBefore('=') }
            .filter { it.isNotBlank() }
            .distinct()
        return JSONObject()
            .put("url", redactSensitiveUrl(url))
            .put("hasCookies", names.isNotEmpty())
            .put("cookieCount", names.size)
            .put("cookieNames", JSONArray().apply { names.forEach { put(it) } })
            .put("valuesRedacted", true)
    }

    private fun cookieVerify(rawUrl: String): JSONObject {
        val status = cookieStatus(rawUrl)
        return status.put("verified", status.optInt("cookieCount") > 0)
    }

    private fun cookieFlush(): JSONObject {
        CookieManager.getInstance().flush()
        return JSONObject().put("flushed", true)
    }

    private fun userScriptAdd(browserDir: File, request: Map<String, String>): JSONObject {
        val id = request["id"]?.takeIf { it.isNotBlank() } ?: "script-${System.currentTimeMillis()}"
        val sourcePath = request.requireValue("path")
        val sourceFile = File(sourcePath)
        require(sourceFile.isFile && sourceFile.canRead()) { "userscript file is unreadable" }
        val scriptsDir = File(browserDir, "userscripts").apply { mkdirs() }
        val targetFile = File(scriptsDir, "$id.js")
        sourceFile.copyTo(targetFile, overwrite = true)
        val scripts = loadUserScripts(browserDir)
            .filterNot { it.id == id }
            .toMutableList()
        val script = BrowserUserScript(
            id = id,
            name = request["name"]?.takeIf { it.isNotBlank() } ?: id,
            match = request["match"]?.takeIf { it.isNotBlank() } ?: "*",
            path = targetFile.absolutePath,
            enabled = request["enabled"] != "0"
        )
        scripts.add(script)
        saveUserScripts(browserDir, scripts)
        activeTabId?.let { tabs[it] }?.let { applyUserScripts(it) }
        return userScriptToJson(script)
    }

    private fun userScriptList(browserDir: File): JSONObject {
        return JSONObject().put("scripts", JSONArray().apply {
            loadUserScripts(browserDir).forEach { put(userScriptToJson(it)) }
        })
    }

    private fun userScriptSetEnabled(browserDir: File, id: String, enabled: Boolean): JSONObject {
        val scripts = loadUserScripts(browserDir).map {
            if (it.id == id) it.copy(enabled = enabled) else it
        }
        require(scripts.any { it.id == id }) { "userscript not found: $id" }
        saveUserScripts(browserDir, scripts)
        return JSONObject().put("id", id).put("enabled", enabled)
    }

    private fun userScriptRemove(browserDir: File, id: String): JSONObject {
        val scripts = loadUserScripts(browserDir)
        val removed = scripts.firstOrNull { it.id == id }
        require(removed != null) { "userscript not found: $id" }
        File(removed.path).delete()
        saveUserScripts(browserDir, scripts.filterNot { it.id == id })
        return JSONObject().put("id", id).put("removed", true)
    }

    private suspend fun click(request: Map<String, String>): JSONObject {
        focusWebView(activeTab().webView)
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
        val script = """
            const selector = $selectorLiteral;
            const target = selector ? document.querySelector(selector) : document.body;
            if (!target) throw new Error('Element not found: ' + selector);
            const text = (target.innerText || target.textContent || '').replace(/\s+/g, ' ').trim();
            return {selector:selector, text:text, textLength:text.length};
            """.trimIndent()
        if (selector.isNullOrBlank()) return evalObject(script)

        var lastError: Throwable? = null
        val deadline = System.currentTimeMillis() + 2500
        while (System.currentTimeMillis() <= deadline) {
            try {
                return evalObject(script)
            } catch (error: Throwable) {
                lastError = error
                if (!error.message.orEmpty().contains("Element not found")) throw error
                delay(150)
            }
        }
        throw lastError ?: IllegalStateException("Element not found: $selector")
    }

    private suspend fun getReadable(): JSONObject = getText("main, article, [role='main'], body")

    private suspend fun executeJs(script: String): JSONObject = evalObject(
        """
        const source = ${JSONObject.quote(script)};
        let value;
        try {
          value = window.eval(source);
        } catch (expressionError) {
          if (!(expressionError instanceof SyntaxError)) {
            throw expressionError;
          }
          value = (new Function(source)).call(window);
        }
        function codexValueToString(value) {
          if (value === undefined) return '';
          if (typeof value === 'string') return value;
          if (value !== null && typeof value === 'object') {
            try { return JSON.stringify(value); } catch (_) {}
          }
          return String(value);
        }
        return {value: codexValueToString(value).slice(0, 4000)};
        """.trimIndent()
    )

    private suspend fun screenshot(
        browserDir: File,
        requestId: String,
        request: Map<String, String>
    ): JSONObject {
        val tab = activeTab()
        val file = File(browserDir, "screenshots/$requestId.png")
        var captureWidth = 0
        var captureHeight = 0
        val bytesWritten = withContext(Dispatchers.Main.immediate) {
            val parent = tab.webView.parent as? ViewGroup
            val (targetWidth, targetHeight) = captureSizeFor(tab.webView)
            val offscreenHost = if (parent == null) {
                attachOffscreenCaptureHost(tab, targetWidth, targetHeight)
            } else {
                null
            }
            try {
                val (width, height) = layoutWebView(tab.webView)
                captureWidth = width
                captureHeight = height
                prepareWebViewForCapture(tab.webView)
                val pageTextSnapshot = pageTextSnapshot(tab.webView)
                val bitmap = captureWebViewBitmap(tab.webView, width, height, pageTextSnapshot)
                withContext(Dispatchers.IO) {
                    file.parentFile?.mkdirs()
                    FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    file.length()
                }.also {
                    bitmap.recycle()
                }
            } finally {
                detachOffscreenCaptureHost(tab, offscreenHost)
            }
        }
        val pushToFiles = request["push"] == "1" || request["to_files"] == "1"
        val fileId = request["file_id"]?.takeIf { it.isNotBlank() } ?: requestId
        return JSONObject()
            .put("path", file.absolutePath)
            .put("bytes", bytesWritten)
            .put("width", captureWidth)
            .put("height", captureHeight)
            .put("pushToFiles", pushToFiles)
            .put("presentFiles", request["present_files"] != "0")
            .put("fileId", fileId)
            .put("name", "browser-$requestId.png")
    }

    private fun openAuthBrowser(request: Map<String, String>, requestId: String, action: String): JSONObject {
        val url = normalizeUrl(request.requireValue("url"))
        val reason = request["reason"].orEmpty().ifBlank { "安全登录/验证" }
        val code = request["code"].orEmpty()
        val openNow = request["open_now"] == "1" ||
            request["auto_open"] == "1" ||
            action in setOf("external", "auth", "custom_tab")
        authTask = BrowserAuthTask(
            requestId = requestId,
            url = url,
            reason = reason,
            code = code,
            userAction = if (openNow) "opened" else "created"
        )
        needsUser = true
        userMessage = reason
        activeUserRequestId = requestId
        publish("waiting_for_user", reason)
        if (openNow) {
            launchCustomTab(url)
        }
        return authTaskJson()
            .put("url", redactSensitiveUrl(url))
            .put("external", openNow)
            .put("openNow", openNow)
    }

    private fun reopenAuthBrowser(request: Map<String, String>, requestId: String): JSONObject {
        val task = authTask
        val url = request["url"]?.takeIf { it.isNotBlank() }?.let(::normalizeUrl)
            ?: task?.url
            ?: throw IllegalStateException("没有可重新打开的 Auth 任务")
        val resolvedTask = task ?: BrowserAuthTask(
            requestId = requestId,
            url = url,
            reason = request["reason"].orEmpty().ifBlank { "安全登录/验证" },
            code = request["code"].orEmpty()
        )
        resolvedTask.state = "reopened"
        resolvedTask.userAction = "reopen"
        resolvedTask.active = true
        authTask = resolvedTask
        needsUser = true
        userMessage = resolvedTask.reason
        activeUserRequestId = resolvedTask.requestId
        publish("reopened", resolvedTask.reason)
        launchCustomTab(url)
        return authTaskJson().put("url", redactSensitiveUrl(url))
    }

    private fun launchCustomTab(url: String) {
        val uri = Uri.parse(url)
        Handler(Looper.getMainLooper()).post {
            val opened = runCatching {
                CustomTabsIntent.Builder()
                    .setShowTitle(true)
                    .build()
                    .launchUrl(initialContext, uri)
            }.recoverCatching {
                initialContext.startActivity(
                    Intent(Intent.ACTION_VIEW, uri)
                        .addCategory(Intent.CATEGORY_BROWSABLE)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }.isSuccess
            if (!opened) {
                authTask?.apply {
                    state = "error"
                    userAction = "open_failed"
                    active = false
                }
                needsUser = false
                userMessage = ""
                publish("error", "没有可打开登录页面的浏览器")
            }
        }
    }

    private fun authDone(requestId: String): JSONObject {
        val task = authTask ?: BrowserAuthTask(
            requestId = requestId,
            url = "",
            reason = "安全登录/验证",
            code = ""
        )
        task.state = "user_done"
        task.userAction = "done"
        task.active = false
        authTask = task
        needsUser = false
        userMessage = ""
        activeUserRequestId = ""
        publish("user_done", "用户已完成安全登录/验证")
        return authTaskJson()
    }

    private fun authCancelled(requestId: String): JSONObject {
        val task = authTask ?: BrowserAuthTask(
            requestId = requestId,
            url = "",
            reason = "安全登录/验证",
            code = ""
        )
        task.state = "cancelled"
        task.userAction = "cancel"
        task.active = false
        authTask = task
        needsUser = false
        userMessage = ""
        activeUserRequestId = ""
        publish("cancelled", "用户已取消安全登录/验证")
        return authTaskJson()
    }

    private fun authCollapsed(requestId: String): JSONObject {
        val task = authTask ?: BrowserAuthTask(
            requestId = requestId,
            url = "",
            reason = "安全登录/验证",
            code = ""
        )
        task.state = "collapsed"
        task.userAction = "collapse"
        task.active = true
        authTask = task
        needsUser = true
        userMessage = task.reason
        activeUserRequestId = task.requestId
        publish("collapsed", task.reason)
        return authTaskJson()
    }

    private fun authTaskJson(): JSONObject {
        val task = authTask
        return JSONObject()
            .put("auth", task != null)
            .put("authRequestId", task?.requestId.orEmpty())
            .put("authUrl", redactSensitiveUrl(task?.url.orEmpty()))
            .put("authReason", task?.reason.orEmpty())
            .put("authCode", redactAuthCode(task?.code.orEmpty()))
            .put("authState", task?.state.orEmpty())
            .put("userAction", task?.userAction.orEmpty())
            .put("active", task?.active == true)
            .put("valuesRedacted", true)
    }

    private fun userWait(message: String, requestId: String): JSONObject {
        needsUser = true
        userMessage = message
        activeUserRequestId = requestId
        publish("waiting_for_user", message)
        return JSONObject().put("message", message)
    }

    private fun userDone(): JSONObject {
        needsUser = false
        userMessage = ""
        activeUserRequestId = ""
        publish("done", "用户已完成接管")
        return JSONObject().put("userDone", true)
    }

    private fun userCollapse(): JSONObject {
        publish("collapsed", "用户已折叠，仍等待处理")
        return JSONObject()
            .put("userAction", "collapse")
            .put("collapsed", true)
    }

    private fun userCancelled(): JSONObject {
        needsUser = false
        userMessage = ""
        activeUserRequestId = ""
        externalOpenPrompt = null
        publish("cancelled", "用户已取消接管")
        return JSONObject().put("userCancelled", true)
    }

    private fun confirmExternalOpen(requestId: String): JSONObject {
        val prompt = externalOpenPrompt ?: return JSONObject()
            .put("externalOpen", false)
            .put("userAction", "missing")
        if (requestId.isNotBlank() && requestId != prompt.requestId) {
            return JSONObject()
                .put("externalOpen", false)
                .put("userAction", "ignored")
                .put("expectedRequestId", prompt.requestId)
        }
        externalOpenPrompt = null
        needsUser = false
        userMessage = ""
        var fallbackHandled = false
        val opened = prompt.intent?.let { intent ->
            runCatching {
                initialContext.startActivity(intent)
            }.onFailure { error ->
                val fallbackUrl = sanitizeHttpFallback(prompt.fallbackUrl)
                if (error is ActivityNotFoundException && fallbackUrl.isNotBlank()) {
                    activeTabId?.let { tabs[it]?.webView?.loadUrl(fallbackUrl) }
                    fallbackHandled = true
                }
            }.isSuccess
        } == true || fallbackHandled
        val successMessage = when {
            fallbackHandled -> "没有外部应用，已在浏览器打开备用链接"
            prompt.kind == "download" -> "已交给系统下载/打开"
            else -> "已打开外部链接"
        }
        publish(if (opened) "done" else "cancelled", if (opened) successMessage else "没有可处理的外部链接")
        return JSONObject()
            .put("externalOpen", opened)
            .put("userAction", "confirm")
            .put("target", redactSensitiveUrl(prompt.target))
            .put("scheme", prompt.scheme)
            .put("fallbackUrl", redactSensitiveUrl(sanitizeHttpFallback(prompt.fallbackUrl)))
            .put("fallbackHandled", fallbackHandled)
            .put("kind", prompt.kind)
            .put("valuesRedacted", true)
    }

    private fun cancelExternalOpen(requestId: String): JSONObject {
        val prompt = externalOpenPrompt ?: return JSONObject()
            .put("externalOpen", false)
            .put("userAction", "missing")
        if (requestId.isNotBlank() && requestId != prompt.requestId) {
            return JSONObject()
                .put("externalOpen", false)
                .put("userAction", "ignored")
                .put("expectedRequestId", prompt.requestId)
        }
        externalOpenPrompt = null
        needsUser = false
        userMessage = ""
        publish("cancelled", "用户已取消打开外部链接")
        return JSONObject()
            .put("externalOpen", false)
            .put("userAction", "cancel")
            .put("target", redactSensitiveUrl(prompt.target))
            .put("scheme", prompt.scheme)
            .put("fallbackUrl", redactSensitiveUrl(sanitizeHttpFallback(prompt.fallbackUrl)))
            .put("kind", prompt.kind)
            .put("valuesRedacted", true)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createTab(): BrowserTab {
        val tabId = ++nextTabId
        val contextWrapper = MutableContextWrapper(initialContext)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            runCatching { WebView.enableSlowWholeDocumentDraw() }
        }
        val webView = CapturableWebView(contextWrapper).apply {
            setBackgroundColor(Color.WHITE)
            setWillNotDraw(false)
            isFocusable = true
            isFocusableInTouchMode = true
            settings.javaScriptEnabled = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowContentAccess = false
            settings.allowFileAccess = false
            settings.allowFileAccessFromFileURLs = false
            settings.allowUniversalAccessFromFileURLs = false
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            settings.loadsImagesAutomatically = true
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.setSupportMultipleWindows(true)
            settings.setSupportZoom(true)
            settings.builtInZoomControls = true
            settings.displayZoomControls = false
            settings.mediaPlaybackRequiresUserGesture = false
            settings.setGeolocationEnabled(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settings.safeBrowsingEnabled = true
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        }
        val tab = BrowserTab(id = tabId, contextWrapper = contextWrapper, webView = webView)
        webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView?, title: String?) {
                tab.title = title.orEmpty().ifBlank { tab.currentUrl }
                publish()
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                val child = runCatching { createTab() }.getOrNull() ?: return false
                activeTabId = child.id
                attachedContainer?.let { attachTo(it as FrameLayout) }
                val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                transport.webView = child.webView
                resultMsg.sendToTarget()
                publish("running", "已打开新窗口")
                return true
            }

            override fun onCloseWindow(window: WebView?) {
                val id = tabs.values.firstOrNull { it.webView === window }?.id
                closeTab(id)
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: WebChromeClient.FileChooserParams?
            ): Boolean {
                val launcher = launchFileChooser ?: return false
                val intent = runCatching {
                    fileChooserParams?.createIntent()
                }.getOrNull() ?: Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                needsUser = true
                userMessage = "请选择网页要上传的文件"
                launcher(intent) { uris ->
                    needsUser = false
                    userMessage = ""
                    filePathCallback?.onReceiveValue(uris)
                    publish("done", "文件选择已返回")
                }
                publish("waiting_for_user", userMessage)
                return true
            }

            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                showJsDialog(message.orEmpty(), result)
                return true
            }

            override fun onJsConfirm(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                showJsDialog(message.orEmpty(), result, cancelable = true)
                return true
            }

            override fun onJsPrompt(
                view: WebView?,
                url: String?,
                message: String?,
                defaultValue: String?,
                result: JsPromptResult?
            ): Boolean {
                showJsPrompt(message.orEmpty(), defaultValue.orEmpty(), result)
                return true
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                return shouldHandleOutsideWebView(request?.url?.toString().orEmpty(), tab)
            }

            @Deprecated("Deprecated in Android API")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                return shouldHandleOutsideWebView(url.orEmpty(), tab)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                val startedUrl = url.orEmpty()
                tab.currentUrl = startedUrl
                tab.loadingMainFrameUrl = startedUrl
                tab.loadStartedToken = tab.loadWaiterToken
                tab.isLoading = true
                publish("running", "加载中")
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                val finishedUrl = url.orEmpty().ifBlank { tab.currentUrl }
                if (tab.loadWaiter != null &&
                    tab.loadingMainFrameUrl.isNotBlank() &&
                    !urlsSameForLoad(finishedUrl, tab.loadingMainFrameUrl)
                ) {
                    return
                }
                tab.currentUrl = finishedUrl
                tab.title = view?.title.orEmpty().ifBlank { tab.currentUrl }
                tab.isLoading = false
                detectRiskChallenge(tab, bodyText = "")
                view?.evaluateJavascript(
                    "(function(){return (document.body&&document.body.innerText||'').slice(0,4000);})();"
                ) { raw ->
                    detectRiskChallenge(tab, bodyText = decodeJsString(raw))
                }
                cookieFlush()
                appendHistory(tab)
                val finishedToken = tab.loadWaiterToken
                val shouldCompleteWaiter = tab.loadWaiter != null &&
                    tab.loadStartedToken == finishedToken &&
                    urlsSameForLoad(finishedUrl, tab.loadingMainFrameUrl)
                if (shouldCompleteWaiter) {
                    completeLoadWaiterIfCurrent(tab, finishedToken)
                }
                publish("done", "网页已加载")
                applyUserScripts(tab) { error ->
                    if (!error.isNullOrBlank()) {
                        tab.lastError = error
                    }
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request?.isForMainFrame != false) {
                    val errorUrl = request?.url?.toString().orEmpty()
                    if (tab.loadWaiter != null &&
                        tab.loadingMainFrameUrl.isNotBlank() &&
                        errorUrl.isNotBlank() &&
                        !urlsSameForLoad(errorUrl, tab.loadingMainFrameUrl)
                    ) {
                        return
                    }
                    tab.lastError = error?.description?.toString()
                    tab.isLoading = false
                    tab.loadWaiter?.complete(Unit)
                    tab.loadWaiter = null
                    tab.loadStartedToken = 0L
                    tab.loadingMainFrameUrl = ""
                    publish("error", tab.lastError.orEmpty())
                }
            }
        }
        webView.setDownloadListener { url, _, _, _, _ ->
            handleDownloadUrl(url, tab)
        }
        tabs[tabId] = tab
        activeTabId = tabId
        publish("done", "浏览器已创建")
        return tab
    }

    private fun shouldHandleOutsideWebView(rawUrl: String, tab: BrowserTab): Boolean {
        val url = rawUrl.trim()
        if (url.isBlank()) return false
        val scheme = Uri.parse(url).scheme.orEmpty().lowercase()
        if (scheme.isBlank()) return false
        if (scheme in WEBVIEW_SCHEMES) return false

        val externalIntent = runCatching {
            if (scheme == "intent") {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
            }.apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setComponent(null)
                setSelector(null)
            }
        }.getOrNull()

        val fallbackUrl = sanitizeHttpFallback(externalIntent?.getStringExtra("browser_fallback_url"))
        if (externalIntent != null) {
            showExternalOpenPrompt(
                target = url,
                scheme = scheme,
                fallbackUrl = fallbackUrl,
                intent = externalIntent,
                kind = "external"
            )
        } else {
            tab.lastError = "设备没有可处理的外部链接：$scheme"
            publish("error", tab.lastError.orEmpty())
        }
        return true
    }

    private fun handleDownloadUrl(rawUrl: String?, tab: BrowserTab) {
        val url = rawUrl?.trim().orEmpty()
        if (url.isBlank()) return
        val uri = Uri.parse(url)
        val scheme = uri.scheme.orEmpty().lowercase()
        val intent = runCatching {
            Intent(Intent.ACTION_VIEW, uri)
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .apply {
                    setComponent(null)
                    setSelector(null)
                }
        }.getOrNull()
        if (intent == null) {
            tab.lastError = "无法处理下载链接"
            publish("error", tab.lastError.orEmpty())
            return
        }
        showExternalOpenPrompt(
            target = url,
            scheme = scheme.ifBlank { "download" },
            fallbackUrl = "",
            intent = intent,
            kind = "download"
        )
    }

    private fun showExternalOpenPrompt(
        target: String,
        scheme: String,
        fallbackUrl: String,
        intent: Intent?,
        kind: String
    ) {
        externalOpenPrompt = BrowserExternalOpenPrompt(
            requestId = "external-${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}",
            target = target,
            scheme = scheme,
            fallbackUrl = sanitizeHttpFallback(fallbackUrl),
            intent = intent,
            kind = kind
        )
        needsUser = true
        userMessage = if (kind == "download") {
            "是否下载/打开文件：$scheme"
        } else {
            "是否打开外部链接：$scheme"
        }
        publish("waiting_for_user", userMessage)
    }

    private fun showJsDialog(
        message: String,
        result: JsResult?,
        cancelable: Boolean = false
    ) {
        runCatching {
            AlertDialog.Builder(initialContext)
                .setMessage(message.ifBlank { "网页消息" })
                .setPositiveButton(android.R.string.ok) { _, _ -> result?.confirm() }
                .apply {
                    if (cancelable) {
                        setNegativeButton(android.R.string.cancel) { _, _ -> result?.cancel() }
                    }
                }
                .setOnCancelListener {
                    if (cancelable) result?.cancel() else result?.confirm()
                }
                .show()
        }.onFailure {
            result?.confirm()
        }
    }

    private fun showJsPrompt(
        message: String,
        defaultValue: String,
        result: JsPromptResult?
    ) {
        runCatching {
            val input = EditText(initialContext).apply {
                setSingleLine()
                setText(defaultValue)
                setSelection(text.length)
            }
            AlertDialog.Builder(initialContext)
                .setMessage(message.ifBlank { "网页输入" })
                .setView(input)
                .setPositiveButton(android.R.string.ok) { _, _ ->
                    result?.confirm(input.text.toString())
                }
                .setNegativeButton(android.R.string.cancel) { _, _ -> result?.cancel() }
                .setOnCancelListener { result?.cancel() }
                .show()
        }.onFailure {
            result?.cancel()
        }
    }

    private fun detectRiskChallenge(tab: BrowserTab, bodyText: String) {
        val haystack = listOf(tab.title, tab.currentUrl, bodyText)
            .joinToString(" ")
            .replace(Regex("\\s+"), " ")
            .lowercase()
        if (haystack.isBlank()) return
        val challenge = when {
            "cloudflare" in haystack &&
                ("challenge" in haystack || "attention required" in haystack) ->
                "cloudflare_challenge"
            "recaptcha" in haystack ||
                "hcaptcha" in haystack ||
                "turnstile" in haystack ||
                "captcha" in haystack ||
                "verify you are human" in haystack ||
                "security check" in haystack ->
                "captcha_challenge"
            "unusual traffic" in haystack ||
                "automated queries" in haystack ->
                "search_engine_challenge"
            "too many requests" in haystack ||
                "rate limit" in haystack ||
                "429" in haystack ->
                "rate_limited"
            "access denied" in haystack ||
                "403 forbidden" in haystack ->
                "access_denied"
            else -> ""
        }
        if (challenge.isBlank()) return
        tab.riskChallengeDetected = true
        tab.riskChallengeKind = challenge
        tab.recommendedNextAction = when (challenge) {
            "rate_limited" -> "wait_before_retrying_and_reduce_request_rate"
            "access_denied" -> "stop_automatic_retry_and_use_manual_access"
            else -> "ask_user_to_complete_verification_manually"
        }
        needsUser = true
        userMessage = when (challenge) {
            "rate_limited" -> "页面触发频率限制，请稍后再继续"
            "access_denied" -> "页面拒绝自动访问，请手动处理"
            else -> "检测到验证码/风控，请手动处理"
        }
        publish("waiting_for_user", userMessage)
    }

    private fun activeTab(): BrowserTab {
        return tabs[activeTabId] ?: tabs.values.lastOrNull() ?: createTab()
    }

    private fun clearCompletedUserTasksForPageAction(action: String) {
        if (action !in PAGE_STATE_ACTIONS) return
        if (authTask?.active == false) {
            authTask = null
        }
        if (!needsUser && authTask == null && externalOpenPrompt == null) {
            userMessage = ""
            activeUserRequestId = ""
        }
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
        val auth = authTask
        val external = externalOpenPrompt
        val snapshotStatus = when {
            auth != null && (auth.active || auth.state in setOf("user_done", "cancelled", "collapsed", "reopened", "error")) -> auth.state
            status == "collapsed" -> "collapsed"
            external != null -> "waiting_for_user"
            needsUser -> "waiting_for_user"
            else -> status
        }
        val snapshotMessage = when {
            auth != null && auth.active -> auth.reason
            external != null -> userMessage
            needsUser -> userMessage
            else -> message
        }
        val snapshot = TerminalBrowserSnapshot(
            available = tabs.isNotEmpty() || auth != null || external != null,
            requestId = auth?.requestId ?: activeUserRequestId.ifBlank { currentRequestId },
            activeTabId = active?.id,
            title = active?.title.orEmpty(),
            currentUrl = redactSensitiveUrl(auth?.url ?: active?.currentUrl.orEmpty()),
            isLoading = active?.isLoading == true,
            status = snapshotStatus,
            message = snapshotMessage,
            needsUser = needsUser || auth?.active == true || external != null,
            lastError = active?.lastError,
            tabs = tabs.values.map {
                TerminalBrowserTabSnapshot(
                    id = it.id,
                    title = it.title,
                    url = redactSensitiveUrl(it.currentUrl),
                    isLoading = it.isLoading
                )
            },
            authTask = auth?.let {
                TerminalBrowserAuthSnapshot(
                    requestId = it.requestId,
                    url = redactSensitiveUrl(it.url),
                    reason = it.reason,
                    code = it.code,
                    state = it.state,
                    userAction = it.userAction,
                    active = it.active
                )
            },
            externalPrompt = external?.let {
                TerminalBrowserExternalPromptSnapshot(
                    requestId = it.requestId,
                    target = redactSensitiveUrl(it.target),
                    scheme = it.scheme,
                    fallbackUrl = redactSensitiveUrl(it.fallbackUrl),
                    kind = it.kind
                )
            },
            riskChallengeDetected = active?.riskChallengeDetected == true,
            riskChallengeKind = active?.riskChallengeKind.orEmpty(),
            recommendedNextAction = active?.recommendedNextAction.orEmpty()
        )
        if (snapshot == latestSnapshot) return
        latestSnapshot = snapshot
        onSnapshot(snapshot)
    }

    private fun completeLoadWaiterIfCurrent(tab: BrowserTab, token: Long): Boolean {
        val waiter = tab.loadWaiter ?: return false
        if (tab.loadWaiterToken != token) return false
        waiter.complete(Unit)
        tab.loadWaiter = null
        tab.loadStartedToken = 0L
        tab.loadingMainFrameUrl = ""
        return true
    }

    private fun appendHistory(tab: BrowserTab) {
        val browserDir = currentBrowserDir ?: return
        if (tab.currentUrl.isBlank() || tab.currentUrl == "about:blank") return
        runCatching {
            browserDir.mkdirs()
            File(browserDir, "history.jsonl").appendText(
                JSONObject()
                    .put("timestamp", System.currentTimeMillis())
                    .put("tabId", tab.id)
                    .put("title", tab.title)
                    .put("url", redactSensitiveUrl(tab.currentUrl))
                    .toString() + "\n"
            )
        }
    }

    private fun applyUserScripts(tab: BrowserTab, onComplete: ((String?) -> Unit)? = null) {
        val browserDir = currentBrowserDir
        if (browserDir == null) {
            onComplete?.invoke(null)
            return
        }
        val scripts = loadUserScripts(browserDir)
            .filter { it.enabled && userScriptMatches(it.match, tab.currentUrl) }
        if (scripts.isEmpty()) {
            onComplete?.invoke(null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var pending = scripts.size
        var firstError: String? = null
        fun finishOne(script: BrowserUserScript, ok: Boolean, error: String?, raw: String?) {
            recordUserScriptResult(browserDir, tab, script, ok, error, raw)
            if (!ok && firstError == null) {
                firstError = "userscript ${script.name} failed: ${error ?: "unknown error"}"
            }
            pending -= 1
            if (pending <= 0) {
                onComplete?.invoke(firstError)
            }
        }
        scripts.forEach { script ->
            val source = runCatching { File(script.path).readText() }.getOrNull()
            if (source == null) {
                finishOne(script, ok = false, error = "script file unreadable", raw = null)
                return@forEach
            }
            var finished = false
            fun finishOnce(ok: Boolean, error: String?, raw: String?) {
                if (finished) return
                finished = true
                finishOne(script, ok, error, raw)
            }
            val javascript = buildUserScriptJavascript(script, source)
            val attempts = listOf(150L, 500L, 1000L)
            attempts.forEachIndexed { attemptIndex, delayMs ->
                handler.postDelayed({
                    if (finished) return@postDelayed
                    runCatching {
                        tab.webView.evaluateJavascript(javascript) { raw ->
                            if (finished) return@evaluateJavascript
                            val decoded = decodeJsString(raw)
                            val json = runCatching { JSONObject(decoded) }.getOrNull()
                            val ok = json?.optBoolean("ok", false) == true
                            val error = json?.optString("error")?.takeIf { it.isNotBlank() }
                            if (ok || attemptIndex == attempts.lastIndex) {
                                finishOnce(ok, error, decoded)
                            }
                        }
                    }.onFailure { error ->
                        if (attemptIndex == attempts.lastIndex) {
                            finishOnce(false, error.message, null)
                        }
                    }
                }, delayMs)
            }
            handler.postDelayed({
                finishOnce(false, "callback timeout", null)
            }, 3500L)
        }
    }

    private fun buildUserScriptJavascript(script: BrowserUserScript, source: String): String {
        val quotedId = JSONObject.quote(script.id)
        val quotedName = JSONObject.quote(script.name)
        val quotedSource = JSONObject.quote(source)
        return """
            (function(){
              try {
                function codexRunUserScript(){
                  try {
                    var codexSource = $quotedSource;
                    var codexFn = new Function(codexSource + "\n//# sourceURL=codex-userscript-" + $quotedId + ".js");
                    var codexValue = codexFn.call(window);
                    return {ok:true,id:$quotedId,name:$quotedName,value:codexValue === undefined ? null : String(codexValue)};
                  } catch (error) {
                    return {ok:false,id:$quotedId,name:$quotedName,error:String(error && error.message ? error.message : error)};
                  }
                }
                if (!document.body) {
                  document.addEventListener('DOMContentLoaded', function(){ codexRunUserScript(); }, {once:true});
                  return JSON.stringify({ok:true,id:$quotedId,name:$quotedName,deferred:true});
                }
                return JSON.stringify(codexRunUserScript());
              } catch (error) {
                return JSON.stringify({ok:false,id:$quotedId,name:$quotedName,error:String(error && error.message ? error.message : error)});
              }
            })();
        """.trimIndent()
    }

    private fun recordUserScriptResult(
        browserDir: File,
        tab: BrowserTab,
        script: BrowserUserScript,
        ok: Boolean,
        error: String?,
        raw: String?
    ) {
        runCatching {
            File(browserDir, "userscripts.log").appendText(
                JSONObject()
                    .put("timestamp", System.currentTimeMillis())
                    .put("tabId", tab.id)
                    .put("url", redactSensitiveUrl(tab.currentUrl))
                    .put("scriptId", script.id)
                    .put("scriptName", script.name)
                    .put("ok", ok)
                    .put("error", error)
                    .put("raw", raw?.take(500))
                    .toString() + "\n"
            )
        }
    }

    private fun userScriptMatches(match: String, url: String): Boolean {
        val rules = match
            .split('\n', '\r', ',', ';')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (rules.isEmpty()) return true
        return rules.any { userScriptRuleMatches(it, url) }
    }

    private fun userScriptRuleMatches(rule: String, url: String): Boolean {
        if (rule.isBlank() || rule == "*") return true
        if (!rule.contains('*')) return url.contains(rule)
        val parts = rule.split('*').filter { it.isNotEmpty() }
        var index = 0
        for (part in parts) {
            val found = url.indexOf(part, startIndex = index)
            if (found < 0) return false
            index = found + part.length
        }
        return true
    }

    private fun loadUserScripts(browserDir: File): List<BrowserUserScript> {
        val file = File(browserDir, "userscripts.json")
        if (!file.isFile) return emptyList()
        return runCatching {
            val array = JSONArray(file.readText())
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val id = item.optString("id")
                    val path = item.optString("path")
                    if (id.isBlank() || path.isBlank()) continue
                    add(
                        BrowserUserScript(
                            id = id,
                            name = item.optString("name", id),
                            match = item.optString("match", "*"),
                            path = path,
                            enabled = item.optBoolean("enabled", true)
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun saveUserScripts(browserDir: File, scripts: List<BrowserUserScript>) {
        browserDir.mkdirs()
        val file = File(browserDir, "userscripts.json")
        val tmp = File(browserDir, "userscripts.json.tmp")
        tmp.writeText(JSONArray().apply { scripts.forEach { put(userScriptToJson(it)) } }.toString(2))
        if (!tmp.renameTo(file)) {
            tmp.copyTo(file, overwrite = true)
            tmp.delete()
        }
    }

    private fun userScriptToJson(script: BrowserUserScript): JSONObject {
        return JSONObject()
            .put("id", script.id)
            .put("name", script.name)
            .put("match", script.match)
            .put("path", script.path)
            .put("enabled", script.enabled)
    }

    private fun layoutWebView(webView: WebView): Pair<Int, Int> {
        val (width, height) = captureSizeFor(webView)
        val widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        webView.measure(widthSpec, heightSpec)
        webView.layout(0, 0, width, height)
        return width to height
    }

    private fun captureSizeFor(webView: WebView): Pair<Int, Int> {
        val display = appContext.resources.displayMetrics
        val parent = webView.parent as? View
        val width = listOf(webView.width, webView.measuredWidth, parent?.width ?: 0, display.widthPixels)
            .firstOrNull { it > 0 } ?: 1080
        val height = listOf(webView.height, webView.measuredHeight, parent?.height ?: 0, display.heightPixels)
            .firstOrNull { it > 0 } ?: 1920
        return width to height
    }

    private fun attachOffscreenCaptureHost(
        tab: BrowserTab,
        width: Int,
        height: Int
    ): FrameLayout? {
        val activity = initialContext as? Activity ?: return null
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return null
        val host = FrameLayout(activity).apply {
            setBackgroundColor(Color.WHITE)
            clipChildren = false
            clipToPadding = false
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        tab.contextWrapper.baseContext = activity
        root.addView(host, 0, ViewGroup.LayoutParams(width, height))
        host.addView(
            tab.webView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        val widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        host.measure(widthSpec, heightSpec)
        host.layout(0, 0, width, height)
        tab.webView.measure(widthSpec, heightSpec)
        tab.webView.layout(0, 0, width, height)
        return host
    }

    private fun detachOffscreenCaptureHost(tab: BrowserTab, host: FrameLayout?) {
        if (host == null) return
        (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
        (host.parent as? ViewGroup)?.removeView(host)
        tab.contextWrapper.baseContext = appContext
    }

    private suspend fun pageTextSnapshot(webView: WebView): BrowserPageTextSnapshot {
        return runCatching {
            val raw = webView.evaluate(
                """
                (function(){
                  return JSON.stringify({
                    title: document.title || '',
                    url: location.href || '',
                    text: (document.body && document.body.innerText || '').slice(0, 4000)
                  });
                })();
                """.trimIndent()
            )
            val obj = JSONObject(decodeJsString(raw))
            BrowserPageTextSnapshot(
                title = obj.optString("title"),
                url = obj.optString("url"),
                text = obj.optString("text")
            )
        }.getOrElse {
            BrowserPageTextSnapshot(title = webView.title.orEmpty(), url = webView.url.orEmpty(), text = "")
        }
    }

    private fun captureWebViewBitmap(
        webView: WebView,
        width: Int,
        height: Int,
        pageTextSnapshot: BrowserPageTextSnapshot
    ): Bitmap {
        val originalLayerType = webView.layerType
        var changedLayerType = false
        return try {
            if (originalLayerType != View.LAYER_TYPE_SOFTWARE) {
                webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
                changedLayerType = true
            }
            val drawn = drawWebViewBitmap(webView, width, height)
            if (!isProbablyBlankBitmap(drawn)) {
                drawn
            } else {
                val content = drawWebViewContentBitmap(webView, width, height)
                if (content != null && !isProbablyBlankBitmap(content)) {
                    drawn.recycle()
                    return content
                }
                content?.recycle()
                val picture = captureWebViewPictureBitmap(webView, width, height)
                if (picture != null && !isProbablyBlankBitmap(picture)) {
                    drawn.recycle()
                    picture
                } else {
                    picture?.recycle()
                    val fallback = drawPageTextFallbackBitmap(pageTextSnapshot, width, height)
                    if (fallback != null && !isProbablyBlankBitmap(fallback)) {
                        drawn.recycle()
                        fallback
                    } else {
                        fallback?.recycle()
                        drawn
                    }
                }
            }
        } finally {
            if (changedLayerType) {
                webView.setLayerType(originalLayerType, null)
            }
        }
    }

    private fun drawPageTextFallbackBitmap(
        snapshot: BrowserPageTextSnapshot,
        width: Int,
        height: Int
    ): Bitmap? {
        val title = snapshot.title.trim()
        val url = snapshot.url.trim()
        val body = snapshot.text.trim()
        if (title.isBlank() && url.isBlank() && body.isBlank()) return null
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            val left = (width * 0.08f).coerceAtLeast(48f)
            val right = width - left
            var y = (height * 0.12f).coerceAtLeast(80f)
            val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(32, 33, 36)
                textSize = (width / 28f).coerceIn(34f, 54f)
                isFakeBoldText = true
            }
            val urlPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(95, 99, 104)
                textSize = (width / 52f).coerceIn(20f, 30f)
            }
            val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(32, 33, 36)
                textSize = (width / 44f).coerceIn(24f, 36f)
            }
            if (title.isNotBlank()) {
                y = drawWrappedText(canvas, title, titlePaint, left, right, y, maxLines = 3)
                y += titlePaint.textSize * 0.7f
            }
            if (url.isNotBlank()) {
                y = drawWrappedText(canvas, url, urlPaint, left, right, y, maxLines = 2)
                y += urlPaint.textSize * 1.4f
            }
            if (body.isNotBlank()) {
                drawWrappedText(canvas, body, bodyPaint, left, right, y, maxLines = 18)
            }
        }
    }

    private fun drawWrappedText(
        canvas: Canvas,
        text: String,
        paint: Paint,
        left: Float,
        right: Float,
        startY: Float,
        maxLines: Int
    ): Float {
        val width = (right - left).coerceAtLeast(1f)
        val normalized = text.replace('\r', '\n')
        val lineHeight = paint.fontSpacing * 1.12f
        var y = startY
        var lines = 0
        for (paragraph in normalized.split('\n')) {
            var remaining = paragraph.trim()
            if (remaining.isBlank()) {
                y += lineHeight
                continue
            }
            while (remaining.isNotBlank() && lines < maxLines) {
                val count = paint.breakText(remaining, true, width, null).coerceAtLeast(1)
                val line = remaining.take(count).trimEnd()
                canvas.drawText(line, left, y, paint)
                y += lineHeight
                lines += 1
                remaining = remaining.drop(count).trimStart()
            }
            if (lines >= maxLines) break
        }
        return y
    }

    private fun drawWebViewContentBitmap(webView: WebView, width: Int, height: Int): Bitmap? {
        val capturableWebView = webView as? CapturableWebView ?: return null
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            capturableWebView.drawWebContent(canvas)
        }
    }

    private fun drawWebViewBitmap(webView: WebView, width: Int, height: Int): Bitmap {
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            webView.draw(canvas)
        }
    }

    @Suppress("DEPRECATION")
    private fun captureWebViewPictureBitmap(webView: WebView, width: Int, height: Int): Bitmap? {
        val picture = webView.capturePicture()
        if (picture.width <= 0 || picture.height <= 0) return null
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            val scale = width.toFloat() / picture.width.toFloat()
            canvas.save()
            canvas.scale(scale, scale)
            picture.draw(canvas)
            canvas.restore()
        }
    }

    private fun isProbablyBlankBitmap(bitmap: Bitmap): Boolean {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) return true
        val reference = bitmap.getPixel(width / 2, height / 2)
        val xStep = (width / 40).coerceAtLeast(1)
        val yStep = (height / 40).coerceAtLeast(1)
        var sampled = 0
        var varied = 0
        var dark = 0
        var y = 0
        while (y < height) {
            var x = 0
            while (x < width) {
                val color = bitmap.getPixel(x, y)
                sampled += 1
                if (colorDistance(color, reference) > 18) varied += 1
                if (Color.alpha(color) > 0 &&
                    (Color.red(color) < 180 || Color.green(color) < 180 || Color.blue(color) < 180)
                ) {
                    dark += 1
                }
                x += xStep
            }
            y += yStep
        }
        return sampled > 0 && varied < 3 && dark < 3
    }

    private fun colorDistance(left: Int, right: Int): Int {
        return kotlin.math.abs(Color.red(left) - Color.red(right)) +
            kotlin.math.abs(Color.green(left) - Color.green(right)) +
            kotlin.math.abs(Color.blue(left) - Color.blue(right)) +
            kotlin.math.abs(Color.alpha(left) - Color.alpha(right))
    }

    private suspend fun prepareWebViewForCapture(webView: WebView) {
        resumeHostedWebView(webView)
        webView.requestLayout()
        webView.invalidate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            webView.postInvalidateOnAnimation()
        }
        awaitChoreographerFrame()
        awaitWebViewVisualState(webView)
        delay(120)
        webView.invalidate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            webView.postInvalidateOnAnimation()
        }
        awaitChoreographerFrame()
        awaitWebViewVisualState(webView)
    }

    private suspend fun awaitChoreographerFrame() {
        withTimeoutOrNull(500) {
            suspendCancellableCoroutine<Unit> { continuation ->
                val callback = Choreographer.FrameCallback {
                    if (continuation.isActive) {
                        continuation.resume(Unit)
                    }
                }
                Choreographer.getInstance().postFrameCallback(callback)
                continuation.invokeOnCancellation {
                    Choreographer.getInstance().removeFrameCallback(callback)
                }
            }
        }
    }

    private suspend fun awaitWebViewVisualState(webView: WebView) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val completed = withTimeoutOrNull(800) {
                suspendCancellableCoroutine<Unit> { continuation ->
                    runCatching {
                        webView.postVisualStateCallback(
                            System.nanoTime(),
                            object : WebView.VisualStateCallback() {
                                override fun onComplete(requestId: Long) {
                                    if (continuation.isActive) {
                                        continuation.resume(Unit)
                                    }
                                }
                            }
                        )
                    }.onFailure {
                        if (continuation.isActive) {
                            continuation.resume(Unit)
                        }
                    }
                }
            } != null
            if (completed) return
        }
        delay(180)
    }

    private fun layoutWebViewInContainer(webView: WebView, container: FrameLayout) {
        val width = container.width
        val height = container.height
        if (width <= 0 || height <= 0) return
        val widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        webView.measure(widthSpec, heightSpec)
        webView.layout(0, 0, width, height)
    }

    private suspend fun waitForHostLayout(tab: BrowserTab) {
        repeat(12) {
            val parent = tab.webView.parent as? View
            if (parent != null && parent.width > 0 && parent.height > 0) return
            delay(50)
        }
    }

    private fun resumeHostedWebView(webView: WebView) {
        focusWebView(webView)
        webView.onResume()
        webView.resumeTimers()
        webView.requestLayout()
        webView.invalidate()
        webView.post {
            webView.requestLayout()
            webView.invalidate()
        }
    }

    private fun focusWebView(webView: WebView) {
        webView.isFocusable = true
        webView.isFocusableInTouchMode = true
        webView.requestFocusFromTouch()
        webView.requestFocus()
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
            .put("requestId", snapshot.requestId)
            .put("activeTabId", snapshot.activeTabId)
            .put("title", snapshot.title)
            .put("currentUrl", redactSensitiveUrl(snapshot.currentUrl))
            .put("isLoading", snapshot.isLoading)
            .put("status", snapshot.status)
            .put("message", snapshot.message)
            .put("needsUser", snapshot.needsUser)
            .put("lastError", snapshot.lastError)
            .put("riskChallengeDetected", snapshot.riskChallengeDetected)
            .put("riskChallengeKind", snapshot.riskChallengeKind)
            .put("recommendedNextAction", snapshot.recommendedNextAction)
            .put("authTask", snapshot.authTask?.let {
                JSONObject()
                    .put("requestId", it.requestId)
                    .put("url", redactSensitiveUrl(it.url))
                    .put("reason", it.reason)
                    .put("code", redactAuthCode(it.code))
                    .put("state", it.state)
                    .put("userAction", it.userAction)
                    .put("active", it.active)
                    .put("valuesRedacted", true)
            })
            .put("externalPrompt", snapshot.externalPrompt?.let {
                JSONObject()
                    .put("requestId", it.requestId)
                    .put("target", redactSensitiveUrl(it.target))
                    .put("scheme", it.scheme)
                    .put("fallbackUrl", redactSensitiveUrl(it.fallbackUrl))
                    .put("kind", it.kind)
                    .put("valuesRedacted", true)
            })
            .put("tabs", JSONArray().apply {
                snapshot.tabs.forEach { tab ->
                    put(
                        JSONObject()
                            .put("id", tab.id)
                            .put("title", tab.title)
                            .put("url", redactSensitiveUrl(tab.url))
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

    private fun normalizeCookieUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return activeTab().currentUrl
        if (trimmed.contains("://")) return trimmed
        return normalizeUrl(trimmed)
    }

    private fun sanitizeHttpFallback(raw: String?): String {
        val fallback = raw?.trim().orEmpty()
        if (fallback.isBlank()) return ""
        return if (isHttpOrHttpsUrl(fallback)) fallback else ""
    }

    private fun isHttpOrHttpsUrl(raw: String): Boolean {
        val scheme = runCatching { Uri.parse(raw.trim()).scheme.orEmpty().lowercase() }
            .getOrDefault("")
        return scheme == "http" || scheme == "https"
    }

    private fun urlsSameForLoad(left: String, right: String): Boolean {
        if (right.isBlank()) return true
        return left == right || runCatching {
            Uri.parse(left).normalizeScheme().toString() == Uri.parse(right).normalizeScheme().toString()
        }.getOrDefault(false)
    }

    private fun redactAuthCode(code: String): String {
        val trimmed = code.trim()
        if (trimmed.isBlank()) return ""
        if (trimmed.length <= 4) return "••••"
        return trimmed.take(2) + "••••" + trimmed.takeLast(2)
    }

    private fun redactSensitiveUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return ""
        return runCatching {
            val uri = Uri.parse(trimmed)
            val scheme = uri.scheme.orEmpty().lowercase()
            if (scheme.isNotBlank() && scheme !in setOf("http", "https", "about")) {
                return@runCatching "$scheme:REDACTED"
            }
            val sensitiveKeys = setOf(
                "access_token",
                "auth",
                "authorization",
                "authuser",
                "client_secret",
                "code",
                "id_token",
                "jwt",
                "key",
                "login_hint",
                "login_token",
                "oauth_token",
                "pass_ticket",
                "password",
                "refresh_token",
                "secret",
                "session",
                "sid",
                "sig",
                "signature",
                "skey",
                "state",
                "ticket",
                "token"
            )
            val queryNames = runCatching { uri.queryParameterNames }.getOrDefault(emptySet())
            val hasSensitiveQuery = queryNames.any { it.lowercase() in sensitiveKeys }
            val fragment = uri.encodedFragment.orEmpty()
            val lowerFragment = fragment.lowercase()
            val hasSensitiveFragment = fragment.isNotBlank() &&
                sensitiveKeys.any { lowerFragment.contains(it) || lowerFragment.contains("${it}%3d") }
            if (!hasSensitiveQuery && !hasSensitiveFragment) {
                trimmed
            } else {
                val builder = uri.buildUpon()
                if (hasSensitiveQuery) {
                    builder.clearQuery()
                    queryNames.forEach { key ->
                        val values = uri.getQueryParameters(key)
                        if (values.isEmpty()) {
                            builder.appendQueryParameter(
                                key,
                                if (key.lowercase() in sensitiveKeys) "REDACTED" else ""
                            )
                        } else {
                            values.forEach { value ->
                                builder.appendQueryParameter(
                                    key,
                                    if (key.lowercase() in sensitiveKeys) "REDACTED" else value
                                )
                            }
                        }
                    }
                }
                if (hasSensitiveFragment) {
                    builder.encodedFragment("REDACTED")
                }
                builder.build().toString()
            }
        }.getOrDefault(trimmed)
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

private val WEBVIEW_SCHEMES = setOf("http", "https", "about")

private val PAGE_STATE_ACTIONS = setOf(
    "open",
    "navigate",
    "reload",
    "back",
    "go_back",
    "forward",
    "go_forward",
    "new_tab",
    "select_tab",
    "close_tab",
    "list_tabs",
    "history",
    "clear_history",
    "cookies_status",
    "cookies_verify",
    "cookies_flush",
    "userscript_add",
    "userscript_list",
    "userscript_enable",
    "userscript_disable",
    "userscript_remove",
    "click",
    "type",
    "scroll",
    "get_text",
    "get_readable",
    "execute_js",
    "js",
    "screenshot"
)
