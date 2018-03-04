# Patch for [LLVM.jl](https://github.com/maleadt/LLVM.jl) v0.5.1 on Julia v0.6.2 for Windows

Inpired by the article (in Japanse) (https://qiita.com/SFyomi/items/74e9cb5b440a3af4fba2) which makes [CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl) work on CUDA Toolkit 9.1,
I tried to make CUDAnative.jl work on Windows environment.
After doing a lot of trial and error, I succeed.

[CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl) depends on [LLVM.jl](https://github.com/maleadt/LLVM.jl).
And the document of LLVM.jl says that it is necessary to build Julia from the source files.
However, As the conclusion, it was possible to make LLVM.jl work on [the official Julia binary](https://julialang.org/downloads/) for Windows 64 bit without building from the source files.

# Inatallation
The prerequisite environment is [Julia v0.6.2 Windows 64 bit binary distributaion](https://julialang-s3.julialang.org/bin/winnt/x64/0.6/julia-0.6.2-win64.exe) from [the official download page](https://julialang.org/downloads/).
The result of `versioninfo()` is as follows.

```jl
julia> versioninfo()
Julia Version 0.6.2
Commit d386e40c17* (2017-12-13 18:08 UTC)
Platform Info:
  OS: Windows (x86_64-w64-mingw32)
  CPU: xxxxxxxxxxxxxxxxx
  WORD_SIZE: 64
  BLAS: libopenblas (USE64BITINT DYNAMIC_ARCH NO_AFFINITY Prescott)
  LAPACK: libopenblas64_
  LIBM: libopenlibm
  LLVM: libLLVM-3.9.1 (ORCJIT, broadwell)
```

## 1. Installing [LLVM.jl](https://github.com/maleadt/LLVM.jl) 
First, add LLVM.jl with `Pkg.add`.

```jl
julia> Pkg.add("LLVM")
INFO: Cloning cache of LLVM from https://github.com/maleadt/LLVM.jl.git
INFO: Installing LLVM v0.5.1
INFO: Building LLVM
...
LoadError: Unknown OS
```
You should get an error, because LLVM.jl v0.5.1 is not compatible with the Windows environment.
(The latest version of LLVM.jl v0.9.x takes into consideration the windows environment, but does not work with Julia v0.6.x.)

### Applying patch to LLVM.jl
I made an ad-hoc patch that makes LLVM.jl v0.5.1 work on Windows.
https://github.com/yatra9/LLVM.jl.v0.5.1.patch

Start Julia and execute the following command.

```julia
pkgdir = Pkg.dir("LLVM")
sourceurl = "https://raw.githubusercontent.com/yatra9/LLVM.jl.v0.5.1.patch/v0.0.1/"
repo = LibGit2.GitRepo(pkgdir)
if string(LibGit2.head_oid(repo)) == "c67f4c19e52ca89553ef80fec67700f613b7424d" && !LibGit2.isdirty(repo)
    for path in ("deps/build.jl", "deps/compile.jl", "deps/discover.jl", "deps/llvm-extra/Makefile", "src/LLVM.jl", "src/base.jl")
        download(sourceurl * path, joinpath(pkgdir, split(path, '/')...))
    end
end
```

### (re)build LLVM.jl
(Re)build LLVM.jl

```jl
julia> Pkg.build("LLVM")
```

All tests should pass.

```jl
julia> Pkg.test("LLVM")
```

## 2. Installing [CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl) 
In advance, install NVidia's CUDA Toolkit.
After that, if LLVM.jl is installed, just `Pkg.add` to install CUDAnative.jl.

```jl
julia> Pkg.add("CUDAnative")
```

You can now use GPU. Enjoy!!

# Building LLVM_extras.dll yourself
To make LLVM.jl work, a DLL named LLVM_extras.dll is required.
In the installation procedure above, `Pkg.build("LLVM")` downloads the binary of LLVM_extras.dll that I built from  https://github.com/yatra9/LLVM.jl.v0.5.1.patch/releases.

If you want to build LLVM_extras.dll yourself, uou need to build Julia from source files.

According to the section "Cygwin-to-MinGW cross-compiling" of https://github.com/JuliaLang/julia/blob/v0.6.2/README.windows.md,
build Julia from the source files using the Cygwin environment.

An example of Make.user is shown below.

```
XC_HOST = x86_64-w64-mingw32
override USE_LLVM_SHLIB = 1

# for CPUs newer than HASWELL (including Broadwell, Skylake, KabyLake, CoffeLake, etc.), set OPENBLAS_TARGET_ARCH = HASWELL
OPENBLAS_TARGET_ARCH = HASWELL
```


After successfully building Julia, start Julia and execute up to the above patch.
After that, set the environment variable `LLVM_JL_COMPILE` to `"true"`, then `Pkg.build ("LLVM")` should produce LLVM_extras.dll.

```jl
julia> ENV["LLVM_JL_COMPILE"] = "true"
julia> # ENV["CYGWINROOT"] = "C:\\cygwin64"  # optional
julia> Pkg.build("LLVM")
```


The location of Cygwin is detected automatically, but if it fails, please set the location of Cygwin in environment variable `CYGWINROOT`.

# Windows版 Julia v0.6.2 で [LLVM.jl](https://github.com/maleadt/LLVM.jl) v0.5.1 を動かすためのパッチ

Juliaの[CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl)をCUDA Toolkit 9.1で動かしたという[記事](https://qiita.com/SFyomi/items/74e9cb5b440a3af4fba2)を見て、Windows環境のCUDA9.1でもできるかと思ってやってみました。
いろいろ試行錯誤した結果、なんとか動きました。
[CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl)を動かすには、依存ライブラリである[LLVM.jl](https://github.com/maleadt/LLVM.jl)をいれる必要があるのですが、そのためには、Juliaをソースからビルドする必要がある、ということになっています。
ですが、結論から言うと、自分でビルドすることなく、[公式のダウンロードページ](https://julialang.org/downloads/)にあるv0.6.2のWindows 64bitのバイナリで動かすこともできました。ただし、LLVM.jlにパッチをあてたりと、いろいろと面倒な手順はいります

ちなみに、上の[参考記事](https://qiita.com/SFyomi/items/74e9cb5b440a3af4fba2)では、LLVMのバージョンを4.0.1にする必要があるとのことですが、LLVMは公式の3.9.1のままでも動きました。（LLVM 4.0.1も試したのですが、windows環境では、thread関係のエラー？でsegfaultで落ちてしまって動きません。）

# インストール手順
前提とする環境は、[公式のダウンロードページ](https://julialang.org/downloads/)にあるv0.6.2のWindows 64bitの[バイナリ](https://julialang-s3.julialang.org/bin/winnt/x64/0.6/julia-0.6.2-win64.exe)です。
Juliaを起動して、`versioninfo()` した結果は以下です。

```jl
julia> versioninfo()
Julia Version 0.6.2
Commit d386e40c17* (2017-12-13 18:08 UTC)
Platform Info:
  OS: Windows (x86_64-w64-mingw32)
  CPU: xxxxxxxxxxxxxxxxx
  WORD_SIZE: 64
  BLAS: libopenblas (USE64BITINT DYNAMIC_ARCH NO_AFFINITY Prescott)
  LAPACK: libopenblas64_
  LIBM: libopenlibm
  LLVM: libLLVM-3.9.1 (ORCJIT, broadwell)
```

## 1. [LLVM.jl](https://github.com/maleadt/LLVM.jl) のインストール
まず、LLVM.jl を `Pkg.add` で追加してみます。

```jl
julia> Pkg.add("LLVM")
INFO: Cloning cache of LLVM from https://github.com/maleadt/LLVM.jl.git
INFO: Installing LLVM v0.5.1
INFO: Building LLVM
...（略）
LoadError: Unknown OS
```
とエラーがでるはずです。LLVM.jl の v0.5.1 はWindows環境をいっさい考慮していないので。（最新のLLVM.jl の v0.9.xではwindows環境の考慮もされていますが、Julia v0.6.x では動作しません）

### LLVM.jlにパッチあて
というわけで、LLVM.jlを無理やりWindowsに対応させるパッチを作りました。
https://github.com/yatra9/LLVM.jl.v0.5.1.patch にあります。

Juliaを起動して、以下のコマンドを実行してください。

```julia
pkgdir = Pkg.dir("LLVM")
sourceurl = "https://raw.githubusercontent.com/yatra9/LLVM.jl.v0.5.1.patch/v0.0.1/"
repo = LibGit2.GitRepo(pkgdir)
if string(LibGit2.head_oid(repo)) == "c67f4c19e52ca89553ef80fec67700f613b7424d" && !LibGit2.isdirty(repo)
    for path in ("deps/build.jl", "deps/compile.jl", "deps/discover.jl", "deps/llvm-extra/Makefile", "src/LLVM.jl", "src/base.jl")
        download(sourceurl * path, joinpath(pkgdir, split(path, '/')...))
    end
end
```

### LLVM.jl の build
あらためて、LLVM.jl を build します。

```jl
julia> Pkg.build("LLVM")
```

テストもすべてパスするはずです。

```jl
julia> Pkg.test("LLVM")
```

## 2. [CUDAnative.jl](https://github.com/JuliaGPU/CUDAnative.jl) のインストール
あらかじめ、NVidia の CUDA Toolkit をインストールしておきます。
あとは、LLVM.jl がインストールされていれば、CUDAnative.jl を `Pkg.add` するだけです。

```jl
julia> Pkg.add("CUDAnative")
```

これで、GPU が使えます。

# LLVM_extras.dll を自分でビルドする場合
LLVM.jl を動かすには LLVM_extras.dll というDLLが必要です。
上のインストール手順では、私がビルドした LLVM_extras.dll のバイナリを、
https://github.com/yatra9/LLVM.jl.v0.5.1.patch/releases
からダウンロードしてくるようにしています。

LLVM_extras.dll を自分でビルドするには、Juliaをソースからビルドする必要があります。
https://github.com/JuliaLang/julia/blob/v0.6.2/README.windows.md
のCygwin-to-MinGW cross-compiling というsectionにしたがって、Cygwin環境を用いてJuliaをソースからビルドしてください。
参考までに Make.user を示します。

```
XC_HOST = x86_64-w64-mingw32
override USE_LLVM_SHLIB = 1

#  HASWELL以降のCPU (Broadwell, Skylake, KabyLake, CoffeLake等）は、すべて OPENBLAS_TARGET_ARCH=HASWELL にする
OPENBLAS_TARGET_ARCH = HASWELL
```

Juliaのビルドが無事終了したら、Juliaを起動して、上記のパッチまで実行してください。
その後、環境変数`LLVM_JL_COMPILE` を `"true"` にセットしてから、`Pkg.build("LLVM")` すれば、LLVM_extras.dll ができるはずです。

```jl
julia> ENV["LLVM_JL_COMPILE"] = "true"
julia> # ENV["CYGWINROOT"] = "C:\\cygwin64"  # optional
julia> Pkg.build("LLVM")
```

Cygwin の場所は自動的に検出するようになっていますが、失敗する場合には、環境変数`CYGWINROOT` にCygwinの場所を設定してください。
