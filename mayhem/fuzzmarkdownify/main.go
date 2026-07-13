// libFuzzer entry for the fuzzmarkdownify target. Built as a c-archive with
// -gcflags=all=-d=libfuzzer and linked with clang -fsanitize=fuzzer (see
// mayhem/build.sh).
package main

/*
#include <stddef.h>
#include <stdint.h>
*/
import "C"

import (
	"unsafe"

	"github.com/gohugoio/hugo/mayhem/fuzzing"
)

//export LLVMFuzzerTestOneInput
func LLVMFuzzerTestOneInput(data *C.uint8_t, size C.size_t) C.int {
	var b []byte
	if size > 0 {
		b = unsafe.Slice((*byte)(unsafe.Pointer(data)), int(size))
	}
	fuzzing.Fuzz(b)
	return 0
}

func main() {}
