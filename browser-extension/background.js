// Report only the focused site's hostname. A title hash matches it to the
// focused window without sending or storing the page title or URL.
const host = "rimuru.screentime.tabs"
let port = null
let retryAfter = 0
let serial = 0

function titleKey(title) {
  const value = String(title || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 200).toLowerCase()
  let first = 2166136261
  let second = 5381
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i)
    first = Math.imul(first ^ code, 16777619)
    second = Math.imul(second, 33) ^ code
  }
  return "title:" + (first >>> 0).toString(16) + ":" + (second >>> 0).toString(16)
}

function siteHost(url) {
  try {
    const page = new URL(url)
    if (page.protocol !== "https:" && page.protocol !== "http:") return ""
    return page.hostname.toLowerCase().replace(/^www\./, "")
  } catch (_) {
    return ""
  }
}

function connection() {
  if (port) return port
  if (Date.now() < retryAfter) return null
  const next = chrome.runtime.connectNative(host)
  next.onDisconnect.addListener(() => {
    if (port === next) port = null
    retryAfter = Date.now() + 30000
    chrome.action.setBadgeText({ text: "!" })
    chrome.action.setTitle({ title: "Install the Rimuru native host to track sites" })
  })
  port = next
  return port
}

async function report() {
  const current = ++serial
  try {
    const window = await chrome.windows.getLastFocused()
    const active = window && window.focused && window.id !== chrome.windows.WINDOW_ID_NONE
    const tabs = active ? await chrome.tabs.query({ active: true, windowId: window.id }) : []
    const tab = tabs[0]
    const site = tab ? siteHost(tab.url) : ""
    if (current !== serial) return
    const native = connection()
    if (!native) return
    native.postMessage(tab && site ? {
      active: true,
      host: site,
      titleKey: titleKey(tab.title)
    } : { active: false })
    chrome.action.setBadgeText({ text: "" })
    chrome.action.setTitle({ title: "Rimuru Screen Time Sites is connected" })
  } catch (error) {
    // Browser shutdown or a missing native host is retried on the next update.
  }
}

chrome.tabs.onActivated.addListener(report)
chrome.tabs.onUpdated.addListener(report)
chrome.tabs.onRemoved.addListener(report)
chrome.windows.onFocusChanged.addListener(report)
chrome.windows.onRemoved.addListener(report)
chrome.runtime.onStartup.addListener(report)
chrome.runtime.onInstalled.addListener(report)
setInterval(report, 2000)
report()
