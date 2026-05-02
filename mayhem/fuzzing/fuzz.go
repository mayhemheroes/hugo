// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package fuzzing

import (
	"context"
	"sync"
	"testing"

	"github.com/gohugoio/hugo/hugolib"
	"github.com/gohugoio/hugo/tpl/transform"
)

var (
	fuzzNsOnce sync.Once
	fuzzNs     *transform.Namespace
)

func FuzzMarkdownify(f *testing.F) {
	f.Add("Hello **World!**")
	f.Add("# Title\n\nSome *text*.")

	f.Fuzz(func(t *testing.T, data string) {
		fuzzNsOnce.Do(func() {
			b := hugolib.NewIntegrationTestBuilder(
				hugolib.IntegrationTestConfig{T: t},
			).Build()
			fuzzNs = transform.New(b.H.Deps)
		})
		if fuzzNs != nil {
			_, _ = fuzzNs.Markdownify(context.Background(), data)
		}
	})
}
