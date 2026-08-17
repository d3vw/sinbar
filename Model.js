function formatRate(value) {
  var n = Math.max(0, Number(value) || 0)
  if (n >= 1073741824) return (n / 1073741824).toFixed(1) + "G/s"
  if (n >= 1048576) return (n / 1048576).toFixed(1) + "M/s"
  if (n >= 1024) return (n / 1024).toFixed(1) + "K/s"
  return Math.round(n) + "B/s"
}

function formatRateFixed(value) {
  var n = Math.max(0, Number(value) || 0)
  var units = ["B/s", "K/s", "M/s", "G/s", "T/s", "P/s", "E/s"]
  var unit = 0
  while (n >= 1024 && unit < units.length - 1) {
    n /= 1024
    unit++
  }

  // Keep one decimal only where it adds useful information. The QML lane is
  // fixed-width, so padding the string itself only creates visual dead space.
  var valueText = unit > 0 && n < 10 ? n.toFixed(1) : String(Math.round(n))
  return valueText + units[unit]
}

function formatBytes(value) {
  var n = Math.max(0, Number(value) || 0)
  if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB"
  if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
  if (n >= 1024) return (n / 1024).toFixed(1) + " KB"
  return Math.round(n) + " B"
}

function uptime(startedAt) {
  var start = Number(startedAt) || 0
  if (start <= 0) return ""
  var seconds = Math.max(0, Math.floor((Date.now() - start) / 1000))
  var days = Math.floor(seconds / 86400)
  var hours = Math.floor((seconds % 86400) / 3600)
  var minutes = Math.floor((seconds % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  return minutes + "m"
}

function shortProcess(path) {
  var value = String(path || "")
  if (value === "") return "unknown process"
  var parts = value.split("/")
  return parts[parts.length - 1] || value
}

function connectionTitle(connection) {
  if (!connection) return "Unknown destination"
  return String(connection.Domain || connection.Destination || "Unknown destination")
}

function routeDelay(delay) {
  var value = Number(delay) || 0
  return value > 0 ? value + " ms" : "—"
}

function logLevelName(level) {
  var names = ["PANIC", "FATAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"]
  var index = Number(level)
  return index >= 0 && index < names.length ? names[index] : "INFO"
}

function safeText(value) {
  return String(value === undefined || value === null ? "" : value)
}
