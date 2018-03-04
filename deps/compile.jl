# compilation of extras library

include("select.jl")

const libext = Compat.Sys.isapple() ? "dylib" : Compat.Sys.iswindows() ? "dll" : "so"

# properties of the final location of llvm-extra
const extras_name = "LLVM_extras.$libext"
const extras_dir = joinpath(Pkg.Dir._pkgroot(), "lib", "v$(VERSION.major).$(VERSION.minor)")
const extras_path = joinpath(extras_dir, extras_name)

verbose_run(cmd) = (println(cmd); run(cmd))

function compile_extras(llvm, julia, config)
    debug("Compiling extras library for LLVM $llvm and Julia $julia")

    # properties of the in-tree build of llvm-extra
    extras_src_dir = joinpath(@__DIR__, "llvm-extra")
    extras_src_path = joinpath(extras_src_dir, "libLLVM_extra.$libext")

    if Compat.Sys.iswindows()
        if !haskey(ENV, "LLVM_JL_COMPILE") || uppercase(ENV["LLVM_JL_COMPILE"]) != "TRUE"
            debug("Downloadinf extras library to $extras_path")
            url = "https://github.com/yatra9/LLVM.jl.v0.5.1.patch/releases/download/v0.0.1/LLVM_extras.dll"
            download(url, extras_path)
            return
        end
        cygwindir = "C:\\cygwin64"  # default path
        if haskey(ENV, "CYGWINROOT")
            cygwindir = ENV["CYGWINROOT"]
        else
            # copied from https://github.com/simonbyrne/WinReg.jl
            let
                base = 0x80000002 # HKEY_LOCAL_MACHINE
                path = "SOFTWARE\\Cygwin\\setup"
                valuename = "rootdir"

                keyref = Ref{UInt32}()
                ret = ccall((:RegOpenKeyExW, "advapi32"), stdcall, Clong,
                            (UInt32, Cwstring, UInt32, UInt32, Ref{UInt32}),
                            base, path, 0, 0x20019, keyref)
                if iszero(ret)
                    try
                        dwSize = Ref{UInt32}()
                        dwDataType = Ref{UInt32}()
                        ret = ccall((:RegQueryValueExW, "advapi32"), stdcall, Clong,
                            (UInt32, Cwstring, Ptr{UInt32},
                             Ref{UInt32}, Ptr{UInt8}, Ref{UInt32}),
                            keyref[], valuename, C_NULL,
                            dwDataType, C_NULL, dwSize)
                        @assert iszero(ret)
                        data = Array{UInt8}(dwSize[])
                        ret = ccall((:RegQueryValueExW, "advapi32"), stdcall, Clong,
                            (UInt32, Cwstring, Ptr{UInt32},
                             Ref{UInt32}, Ptr{UInt8}, Ref{UInt32}),
                            keyref[], "rootdir", C_NULL,
                            dwDataType, data, dwSize)
                        @assert iszero(ret)
                        @assert dwDataType[] == 1 || dwDataType[] == 2
                        data_wstr = reinterpret(Cwchar_t, data)
                        data_wstr[end] == 0 && pop!(data_wstr)
                        cygwindir = String(transcode(UInt8, data_wstr))
                    finally
                        ccall((:RegCloseKey, "advapi32"), stdcall, Clong, (UInt32,), keyref[])
                    end
                end
            end
        end
        cygbin = joinpath(cygwindir, "bin")
        cygpathbin = joinpath(cygbin, "cygpath.exe")
        @assert ispath(cygpathbin) "cannot find cygwin. please set cygwin root directory to ENV[\"CYGWINROOT\"]. (e.g. ENV[\"CYGWINROOT\"] = \"C:\\\\cygwin64\""
        cygpath = winpath -> chomp(String(read(`$cygpathbin -u $(winpath)`)))
        envs = ["LLVM_LIBRARY" => cygpath(llvm.path),
                "JULIA_CONFIG" => get(julia.config),
                "JULIA_BINARY" => cygpath(julia.path),
                "PATH" => "$(cygbin);$(ENV["PATH"])",
                "CXX" => "$(Sys.MACHINE)-g++"]
        if isempty(get(llvm.config))
            append!(envs, ["CPPFLAGS" => @sprintf("-I%s -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS",
                                                  cygpath(joinpath(JULIA_HOME, "..", "include"))),
                           "LDFLAGS" => @sprintf("-L%s", cygpath(joinpath(JULIA_HOME, "..", "lib"))),
                           "LDLIBS" => "-lpsapi -lshell32 -lole32 -luuid",
                           "LLVM_CXXFLAGS" => @sprintf("-I%s -D__USING_SJLJ_EXCEPTIONS__ -D__CRT__NO_INLINE -Wall -W -Wno-unused-parameter -Wwrite-strings -Wcast-qual -Wno-missing-field-initializers -pedantic -Wno-long-long -Wno-maybe-uninitialized -Wdelete-non-virtual-dtor -Wno-comment -Werror=date-time -std=gnu++11  -O2 -DNDEBUG  -fno-exceptions -fno-rtti -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS",
                                                       cygpath(joinpath(JULIA_HOME, "..", "include"))),
                           "HAS_RTTI" => "NO",
                           "LLVM_TARGETS" => join(String.(config[:libllvm_targets]), " "),
                           "CLANG_FORMAT" => cygpath(joinpath(JULIA_HOME, "clang-format"))
                          ])
        else
            push!(envs, "LLVM_CONFIG" => cygpath(get(llvm.config)))
        end
    else
        envs = ("LLVM_CONFIG"  => get(llvm.config),  "LLVM_LIBRARY" => llvm.path,
                   "JULIA_CONFIG" => get(julia.config), "JULIA_BINARY" => julia.path)
    end

    cd(extras_src_dir) do
        withenv(envs...) do
            try
                verbose_run(`make -j$(Sys.CPU_CORES+1)`)
                mv(extras_src_path, extras_path; remove_destination=true)
            finally
                verbose_run(`make clean`)
            end
        end
    end

    # sanity check: in the case of a bundled LLVM the library should be loaded by Julia already,
    #               while a system-provided LLVM shouldn't
    libllvm_exclusive = Libdl.dlopen_e(llvm.path, Libdl.RTLD_NOLOAD) == C_NULL
    if use_system_llvm != libllvm_exclusive
        @assert(Libdl.dlopen_e(llvm.path, Libdl.RTLD_NOLOAD) == C_NULL,
                "exclusive access mode does not match requested type of LLVM library (run with TRACE=1 and file an issue)")
    end

    debug("Compiled extra library at $extras_path")
end


#
# Main
#

function compile()
    llvms, wrappers, julia = discover()
    llvm = select_llvm(llvms, wrappers)

    compile_extras(llvm, julia)
end

if realpath(joinpath(pwd(), PROGRAM_FILE)) == realpath(@__FILE__)
    compile()
end
