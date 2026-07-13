// Package fuzzing holds the Mayhem fuzz entry for Hugo's Markdownify template
// func (the code path of the historical `fuzzmarkdownify` target): a full Hugo
// site is built once via hugolib's integration-test builder, then every input
// is rendered through transform.Markdownify (goldmark markdown -> HTML).
package fuzzing

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"

	"github.com/gohugoio/hugo/hugolib"
	"github.com/gohugoio/hugo/tpl/transform"
)

// fuzzTB satisfies testing.TB (via embedding) outside a `go test` process so
// hugolib.NewIntegrationTestBuilder can run inside the libFuzzer binary.
// Failure methods panic so a broken site build aborts loudly instead of being
// silently ignored.
type fuzzTB struct{ testing.TB }

func (fuzzTB) Cleanup(func())                {}
func (fuzzTB) Error(args ...any)             { panic(fmt.Sprint(args...)) }
func (fuzzTB) Errorf(f string, a ...any)     { panic(fmt.Sprintf(f, a...)) }
func (fuzzTB) Fail()                         { panic("fuzzTB.Fail") }
func (fuzzTB) FailNow()                      { panic("fuzzTB.FailNow") }
func (fuzzTB) Failed() bool                  { return false }
func (fuzzTB) Fatal(args ...any)             { panic(fmt.Sprint(args...)) }
func (fuzzTB) Fatalf(f string, a ...any)     { panic(fmt.Sprintf(f, a...)) }
func (fuzzTB) Helper()                       {}
func (fuzzTB) Log(args ...any)               { fmt.Fprintln(os.Stderr, args...) }
func (fuzzTB) Logf(f string, a ...any)       { fmt.Fprintf(os.Stderr, f+"\n", a...) }
func (fuzzTB) Name() string                  { return "fuzzmarkdownify" }
func (fuzzTB) Setenv(key, value string)      { os.Setenv(key, value) }
func (fuzzTB) Skip(args ...any)              {}
func (fuzzTB) SkipNow()                      {}
func (fuzzTB) Skipf(f string, a ...any)      {}
func (fuzzTB) Skipped() bool                 { return false }
func (fuzzTB) TempDir() string {
	d, err := os.MkdirTemp("", "fuzzmarkdownify")
	if err != nil {
		panic(err)
	}
	return d
}

var (
	nsOnce sync.Once
	ns     *transform.Namespace
)

func namespace() *transform.Namespace {
	nsOnce.Do(func() {
		workDir, err := os.MkdirTemp("", "fuzzmarkdownify-site")
		if err != nil {
			panic(err)
		}
		b := hugolib.NewIntegrationTestBuilder(
			hugolib.IntegrationTestConfig{T: fuzzTB{}, WorkingDir: workDir, NeedsOsFS: true},
		).Build()
		ns = transform.New(b.H.Deps)
	})
	return ns
}

// Fuzz is the entry driven by the libFuzzer binary (mayhem/fuzzmarkdownify).
func Fuzz(data []byte) int {
	_, _ = namespace().Markdownify(context.Background(), string(data))
	return 1
}
