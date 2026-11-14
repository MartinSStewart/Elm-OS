# eco/containers

`SeqDict` and `SeqSet` for eco, with the same API and behaviour as
[lamdera/containers](https://github.com/lamdera/containers): any equatable value can be a key,
and `toList`, `foldl` and the rest go in insertion order. The implementation is lamdera's
(Robin Hansen's hash trie, an insertion-order `Array`, and the `JsArray2` kernel), with these changes:

- **Hashing.** `FNV.hash` is a native kernel (`src/eco-containers/FNVExports.cpp`) that walks any value on
  eco's heap: FNV-1a over its content, finished with MurmurHash3's fmix32, bounded so a large key costs
  O(1). It hashes by content, not representation, so it agrees with `==`: boxed and unboxed numbers,
  all six String forms, list cells and chunks, Dicts in key order, SeqDicts in insertion order. The JS
  kernel (`src/Elm/Kernel/FNV.js`) does the same in JavaScript, without lamdera's `SeqDict.toList`
  import cycle.
- **`JsArray2`** forwards to elm/core's `JsArray` kernel, plus `unsafeSet`, `unsafeInsert` and
  `removeIndex` (`src/eco-containers/JsArray2Exports.cpp`).
- **64-bit `Bitwise`.** eco's Bitwise works on 64 bits, so `compressedIndex` masks to 32 bits.
- **No `encodeDict`/`decodeDict`/`encodeSet`/`decodeSet`**: they need lamdera/codecs.

## `==` needs a patched eco

A SeqDict can hold the same entries in the same order and still differ inside: removing an entry
leaves a hole in its insertion-order Array. eco's `==` is one generic runtime function (`Utils.equal`)
for every boxed type, so it must recognise a SeqDict, as it does Dict nodes by their reserved
constructor tag 0xFFFF. `tools/eco-patched/0001-eco-containers.patch` (against eco's v0.2.0-rc3 commit):

- `Compiler/IR/Runtime/CtorTag.elm`: `SeqDict_elm_builtin` of `eco/containers` gets the reserved tag
  0xFFFB.
- `elm-kernel-cpp/src/core/Utils.cpp` + new `core/SeqDict.hpp`: `==` compares two SeqDicts by their
  entries in insertion order. `FNV.hash` uses the same walk.
- `Builder/Stuff.elm`, `Package.elm`: `eco/containers` is a bundled package, found at
  `share/eco/containers/containers-kernel-cpp` like eco/kernel, so no `--local-package` is needed.

`make ECO_PATCHED=1` builds and uses that eco (`tools/build-patched-eco.sh`: about 10 minutes the first
time, needs LLVM/MLIR 21 from apt.llvm.org: `sudo tools/build-patched-eco.sh --install-deps`).
`make ECO_PATCHED=1 test-containers` runs `tests/` natively and in Node. Plain `make`, CI and
`make docker` still use the stock rc3, which has neither the kernel nor the bundled package.

Known gap: in JavaScript (`make dev`), `==` on SeqDicts is still structural. It comes from elm/core's
JS kernel, which only knows Dict and Set; lamdera patches its elm/core for this.

## Upstreaming to eco

1. In eco, `git am tools/eco-patched/0001-eco-containers.patch` (it's against `ECO_COMMIT` in
   versions.mk; rebase as needed).
2. Copy this directory (without `tests/`) to `containers-kernel-cpp/` in eco.
3. CMake, modelled on eco-kernel-cpp: build `src/eco-containers/*.cpp` into an `EcoContainers` archive
   installed in `lib/eco-runtime/project`, list it where `EcoNativeDriver.cpp` links the eco/kernel
   archives (`ecoKernelLibs()`), and install the Elm package to
   `share/eco/containers/containers-kernel-cpp` like eco/kernel's.
4. Add 0xFFFB to `test/scripts/check-ctor-tags.sh`, and `tests/` as an E2E test.
