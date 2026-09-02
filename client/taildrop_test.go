// client/taildrop_test.go
package client

import (
	"os"
	"path/filepath"
	"testing"
)

func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func TestUniquePathFreeName(t *testing.T) {
	dir := t.TempDir()
	if got, want := uniquePath(dir, "report.pdf"), filepath.Join(dir, "report.pdf"); got != want {
		t.Errorf("uniquePath = %q, want %q", got, want)
	}
}

func TestUniquePathAvoidsCollisions(t *testing.T) {
	dir := t.TempDir()
	touch(t, filepath.Join(dir, "report.pdf"))
	if got, want := uniquePath(dir, "report.pdf"), filepath.Join(dir, "report (1).pdf"); got != want {
		t.Errorf("first collision = %q, want %q", got, want)
	}

	touch(t, filepath.Join(dir, "report (1).pdf"))
	touch(t, filepath.Join(dir, "report (2).pdf"))
	if got, want := uniquePath(dir, "report.pdf"), filepath.Join(dir, "report (3).pdf"); got != want {
		t.Errorf("third collision = %q, want %q", got, want)
	}
}

func TestUniquePathExtensionlessName(t *testing.T) {
	dir := t.TempDir()
	touch(t, filepath.Join(dir, "notes"))
	if got, want := uniquePath(dir, "notes"), filepath.Join(dir, "notes (1)"); got != want {
		t.Errorf("uniquePath = %q, want %q", got, want)
	}
}

func TestUniquePathDotfileKeepsWholeName(t *testing.T) {
	// filepath.Ext(".bashrc") is ".bashrc", so a naive stem/ext split would
	// rename to " (1).bashrc" with a leading space.
	dir := t.TempDir()
	touch(t, filepath.Join(dir, ".bashrc"))
	if got, want := uniquePath(dir, ".bashrc"), filepath.Join(dir, ".bashrc (1)"); got != want {
		t.Errorf("uniquePath = %q, want %q", got, want)
	}
}

// A peer controls the file name, so it must never steer the write out of dir.
func TestUniquePathRejectsTraversal(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"../../.bashrc", "/etc/passwd", "..", ".", "", "sub/dir/file.txt"} {
		got := uniquePath(dir, name)
		if parent := filepath.Dir(got); parent != dir {
			t.Errorf("uniquePath(%q) = %q, escaped into %q", name, got, parent)
		}
	}
}
