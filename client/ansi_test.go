package client

import "testing"

func TestAnsi256Color(t *testing.T) {
	tests := []struct {
		name string
		n    int
		want string
	}{
		{"low range reuses 8-color table", 3, "#e5e510"},
		{"low range reuses bright 8-color table", 12, "#3b8eea"},
		{"color cube (matches real sing-box output)", 201, "#ff00ff"},
		{"color cube, all-zero component", 16, "#000000"},
		{"grayscale ramp", 240, "#585858"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ansi256Color(tt.n); got != tt.want {
				t.Errorf("ansi256Color(%d) = %q, want %q", tt.n, got, tt.want)
			}
		})
	}
}

func TestClassifySGR(t *testing.T) {
	tests := []struct {
		name       string
		params     string
		wantColor  string
		wantChange bool
	}{
		{"empty params is a reset", "", "", true},
		{"explicit reset code", "0", "", true},
		{"default foreground code", "39", "", true},
		{"basic 8-color code", "37", "#e5e5e5", true},
		{"bright 8-color code", "91", "#f14c4c", true},
		{"256-color code", "38;5;201", "#ff00ff", true},
		{"truecolor code", "38;2;255;128;0", "#ff8000", true},
		{"bold alone is ignored", "1", "", false},
		{"bold combined with color still applies the color", "1;31", "#cd3131", true},
		{"out-of-range 256-color index is rejected", "38;5;999", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			color, changed := classifySGR(tt.params)
			if color != tt.wantColor || changed != tt.wantChange {
				t.Errorf("classifySGR(%q) = (%q, %v), want (%q, %v)",
					tt.params, color, changed, tt.wantColor, tt.wantChange)
			}
		})
	}
}

func TestColorizeANSI(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		wantPlain string
		wantRich  string
	}{
		{
			name:      "plain text with no ANSI codes",
			raw:       "router: match rule_set=youtube_domain",
			wantPlain: "router: match rule_set=youtube_domain",
			wantRich:  "router: match rule_set=youtube_domain",
		},
		{
			name:      "basic color run with reset",
			raw:       "\x1b[37mDEBUG\x1b[0m rest",
			wantPlain: "DEBUG rest",
			wantRich:  `<font color="#e5e5e5">DEBUG</font> rest`,
		},
		{
			name:      "256-color run (matches real sing-box output shape)",
			raw:       "\x1b[38;5;201m26950329\x1b[0m",
			wantPlain: "26950329",
			wantRich:  `<font color="#ff00ff">26950329</font>`,
		},
		{
			name:      "multiple color runs in one message",
			raw:       "\x1b[37mDEBUG\x1b[0m[13030] \x1b[38;5;201m8ms\x1b[0m router: sniffed",
			wantPlain: "DEBUG[13030] 8ms router: sniffed",
			wantRich:  `<font color="#e5e5e5">DEBUG</font>[13030] <font color="#ff00ff">8ms</font> router: sniffed`,
		},
		{
			name:      "html-sensitive characters escaped in rich, kept raw in plain",
			raw:       "route(a<b & c>d)",
			wantPlain: "route(a<b & c>d)",
			wantRich:  "route(a&lt;b &amp; c&gt;d)",
		},
		{
			name:      "unterminated trailing escape is dropped, not emitted as garbage",
			raw:       "before\x1b[37",
			wantPlain: "before",
			wantRich:  "before",
		},
		{
			name:      "default-foreground reset (39) behaves like full reset",
			raw:       "\x1b[91mred\x1b[39mplain",
			wantPlain: "redplain",
			wantRich:  `<font color="#f14c4c">red</font>plain`,
		},
		{
			name:      "an ignored code does not clobber an already-open span",
			raw:       "\x1b[31mred\x1b[1mstillred\x1b[0mplain",
			wantPlain: "redstillredplain",
			wantRich:  `<font color="#cd3131">redstillred</font>plain`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			plain, rich := colorizeANSI(tt.raw)
			if plain != tt.wantPlain {
				t.Errorf("plain = %q, want %q", plain, tt.wantPlain)
			}
			if rich != tt.wantRich {
				t.Errorf("rich = %q, want %q", rich, tt.wantRich)
			}
		})
	}
}
