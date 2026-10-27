// Package brand holds the words the demo writes on screen that depend on who
// wrote it: the project, shared by every port, the language this port is
// written in, and what that language calls its units of parallel work. A port
// changes Lang and Workers and nothing else, so the images differ only where
// those words are drawn.
package brand

const (
	Project = "BABELTRO"
	Lang    = "GO"
	Workers = "GOROUTINES"
)
