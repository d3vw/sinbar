// client/ansi.go
package client

import (
	"fmt"
	"html"
	"strconv"
	"strings"
)

// ansi16 maps the standard 8-color (SGR 30-37) and bright 8-color (SGR
// 90-97) foreground codes to hex colors, using the same fixed palette values
// common terminal emulators use for xterm-256color.
var ansi16 = map[int]string{
	30: "#000000", 31: "#cd3131", 32: "#0dbc79", 33: "#e5e510",
	34: "#2472c8", 35: "#bc3fbc", 36: "#11a8cd", 37: "#e5e5e5",
	90: "#666666", 91: "#f14c4c", 92: "#23d18b", 93: "#f5f543",
	94: "#3b8eea", 95: "#d670d6", 96: "#29b8db", 97: "#f5f5f5",
}

// ansi256Color returns the hex RGB color for an xterm 256-color palette
// index (0-255): 0-15 reuse the 16-color table above, 16-231 are the 6x6x6
// color cube, 232-255 are the grayscale ramp.
func ansi256Color(n int) string {
	switch {
	case n < 8:
		return ansi16[30+n]
	case n < 16:
		return ansi16[90+(n-8)]
	case n < 232:
		n -= 16
		r := n / 36
		g := (n / 6) % 6
		b := n % 6
		return fmt.Sprintf("#%02x%02x%02x", cubeLevel(r), cubeLevel(g), cubeLevel(b))
	default:
		gray := 8 + 10*(n-232)
		return fmt.Sprintf("#%02x%02x%02x", gray, gray, gray)
	}
}

func cubeLevel(v int) int {
	if v == 0 {
		return 0
	}
	return 55 + 40*v
}

// classifySGR interprets the semicolon-separated parameters of a single SGR
// escape sequence (the part between "\x1b[" and "m"). It returns the
// resulting foreground color ("" for reset/default/no-color) and whether the
// color state changed at all. Codes that don't affect foreground color (bold,
// underline, background colors, unrecognized codes, ...) leave changed=false
// so callers can leave any currently-open color span untouched.
func classifySGR(params string) (color string, changed bool) {
	if params == "" {
		return "", true // bare "\x1b[m" is a reset
	}
	parts := strings.Split(params, ";")
	for i := 0; i < len(parts); i++ {
		code, err := strconv.Atoi(parts[i])
		if err != nil {
			continue
		}
		switch {
		case code == 0:
			color, changed = "", true
		case code == 39:
			color, changed = "", true
		case code >= 30 && code <= 37:
			color, changed = ansi16[code], true
		case code >= 90 && code <= 97:
			color, changed = ansi16[code], true
		case code == 38 && i+2 < len(parts) && parts[i+1] == "5":
			if n, err := strconv.Atoi(parts[i+2]); err == nil && n >= 0 && n <= 255 {
				color, changed = ansi256Color(n), true
			}
			i += 2
		case code == 38 && i+4 < len(parts) && parts[i+1] == "2":
			r, e1 := strconv.Atoi(parts[i+2])
			g, e2 := strconv.Atoi(parts[i+3])
			b, e3 := strconv.Atoi(parts[i+4])
			if e1 == nil && e2 == nil && e3 == nil {
				color, changed = fmt.Sprintf("#%02x%02x%02x", r, g, b), true
			}
			i += 4
		}
	}
	return color, changed
}

// colorizeANSI parses ANSI SGR color escape sequences out of raw sing-box
// log text. It returns plain (escape-free text, safe for the keyword log
// filter to match against) and rich (the same text with color runs wrapped
// in QML rich-text <font color="#rrggbb"> spans, HTML-escaped, suitable for
// Text { textFormat: Text.StyledText }).
func colorizeANSI(raw string) (plain string, rich string) {
	var plainBuilder, richBuilder strings.Builder
	openSpan := false
	i := 0
	for i < len(raw) {
		start := i
		for i < len(raw) && !(raw[i] == 0x1b && i+1 < len(raw) && raw[i+1] == '[') {
			i++
		}
		if i > start {
			text := raw[start:i]
			plainBuilder.WriteString(text)
			richBuilder.WriteString(html.EscapeString(text))
		}
		if i >= len(raw) {
			break
		}
		end := strings.IndexByte(raw[i:], 'm')
		if end == -1 {
			break // truncated/malformed trailing escape; stop rather than emit garbage
		}
		params := raw[i+2 : i+end]
		i += end + 1
		color, changed := classifySGR(params)
		if changed {
			if openSpan {
				richBuilder.WriteString("</font>")
				openSpan = false
			}
			if color != "" {
				richBuilder.WriteString(`<font color="` + color + `">`)
				openSpan = true
			}
		}
	}
	if openSpan {
		richBuilder.WriteString("</font>")
	}
	return plainBuilder.String(), richBuilder.String()
}
