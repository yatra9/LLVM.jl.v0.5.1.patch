# discovery of Julia, LLVM, and LLVM wrappers in LLVM.jl

include("util.jl")


#
# LLVM discovery
#

# possible names for libLLVM given a LLVM version number
function llvm_libnames(version::VersionNumber)
    @static if Compat.Sys.isapple()
        # macOS dylibs are versioned already
        return ["libLLVM.dylib"]
    elseif Compat.Sys.islinux()
        # Linux DSO's aren't versioned, so only use versioned filenames
        return ["libLLVM-$(version.major).$(version.minor).$(version.patch).so",
                "libLLVM-$(version.major).$(version.minor).$(version.patch)svn.so",
                "libLLVM-$(version.major).$(version.minor).so",
                "libLLVM-$(version.major).$(version.minor)svn.so"]
    elseif Compat.Sys.iswindows()
        return ["LLVM.dll"]
    else
        error("Unknown OS")
    end
end

# returns vector of Tuple{path::AbstractString, VersionNumber}
function find_libllvm(dir::AbstractString, versions::Vector{VersionNumber})
    trace("Looking for libllvm in $dir")
    libraries = Vector{Tuple{String, VersionNumber}}()
    for version in versions, name in llvm_libnames(version)
        lib = joinpath(dir, name)
        if ispath(lib)
            trace("- v$version at $lib")
            push!(libraries, tuple(lib, version))
        end
    end

    return libraries
end

# returns vector of Tuple{path::AbstractString, VersionNumber}
function find_llvmconfig(dir::AbstractString)
    trace("Looking for llvm-config in $dir")
    configs = Vector{Tuple{String, VersionNumber}}()
    for file in readdir(dir)
        if startswith(file, "llvm-config")
            path = joinpath(dir, file)
            version = VersionNumber(strip(read(`$path --version`, String)))
            trace("- $version at $path")
            push!(configs, tuple(path, version))
        end
    end

    return configs
end

function discover_llvm(libdirs, configdirs)
    debug("Discovering LLVM libraries in $(join(libdirs, ", ")), and configs in $(join(configdirs, ", "))")
    llvms = Vector{Toolchain}()

    # check for bundled LLVM libraries
    # NOTE: as we only build the extras library from source, these libraries will never be
    #       used, but leave this code here as it may be used if we figure out how to provide
    #       bindeps
    for libdir in unique(libdirs)
        libraries = find_libllvm(libdir, [base_llvm_version])

        for (library, version) in libraries
            push!(llvms, Toolchain(library, version))
        end
    end

    # check for llvm-config binaries in known locations
    for dir in unique(configdirs)
        isdir(dir) || continue
        configs = find_llvmconfig(dir)

        # look for libraries in the reported library directory
        for (config, version) in configs
            libdir = readchomp(`$config --libdir`)
            libraries = find_libllvm(libdir, [version])

            for (library, _) in libraries
                push!(llvms, Toolchain(library, version, config))
            end
        end
    end

    # prune
    llvms = unique(x -> realpath(x.path), llvms)

    debug("Discovered LLVM toolchains: ", join(llvms, ", "))

    return llvms
end

function discover_llvm()
    if Compat.Sys.iswindows()
        return discover_llvm_windows()
    end
    # look for bundled LLVM toolchains relative to JULIA_HOME
    bundled_llvms =
        discover_llvm([joinpath(JULIA_HOME, "..", "lib", "julia")],
                       [JULIA_HOME, joinpath(JULIA_HOME, "..", "tools")])
    for llvm in bundled_llvms
        llvm.props[:bundled] = true
    end

    # look for system LLVM toolchains in the PATH
    system_llvms =
        discover_llvm([],
                      [split(ENV["PATH"], ':')...])
    for llvm in system_llvms
        llvm.props[:bundled] = false
    end

    return [bundled_llvms; system_llvms]
end

function discover_llvm_windows()
    @assert v"0.6" <= VERSION < v"0.7-" "This patch is only for Julia v0.6.x"
    libdirs = [JULIA_HOME, joinpath(JULIA_HOME, "..", "lib")]
    configdirs = [JULIA_HOME, joinpath(JULIA_HOME, "..", "tools")]

    # check for llvm-config binaries in known locations
    config = ""
    for dir in unique(configdirs)
        isdir(dir) || continue
        configs = find_llvmconfig(dir)
        if !isempty(configs)
            config = first(first(configs))
            break
        end
    end

    # look for bundled LLVM toolchains relative to JULIA_HOME
    llvms = Vector{Toolchain}()
    for libdir in unique(libdirs)
        libraries = find_libllvm(libdir, [base_llvm_version])
        for (library, version) in libraries
            push!(llvms, Toolchain(library, version, config))
            llvms[end].props[:bundled] = true
        end
    end
    return llvms
end


#
# Julia discovery
#

function discover_julia()
    julia_cmd = Base.julia_cmd()
    julia = Toolchain(julia_cmd.exec[1], Base.VERSION,
                      joinpath(JULIA_HOME, "..", "share", "julia", "julia-config.jl"))
    isfile(julia.path) || error("could not find Julia binary from command $julia_cmd")
    if !isfile(get(julia.config)) && julia.version.minor == 5
        # HACK for 0.5: non-installed builds are incomplete (see JuliaLang/julia#19002)
        #               so we include those in-tree paths here
        root = joinpath(JULIA_HOME, "..", "..")
        julia = Toolchain(julia.path, julia.version, joinpath(root, "contrib", "julia-config.jl"))
        ENV["EXTRA_CXXFLAGS"] = join(
            map(dir->"-I"*joinpath(root, dir), ["src", "src/support", "usr/include"]), " ")
    end
    isfile(get(julia.config)) || error("could not find julia-config.jl relative to $(JULIA_HOME)")

    return julia
end


#
# LLVM wrapper discovery
#

function discover_wrappers()
    return map(dir->VersionNumber(dir),
               filter(path->isdir(joinpath(@__DIR__, "..", "lib", path)),
                      readdir(joinpath(@__DIR__, "..", "lib"))))
end


#
# Main
#

function discover()
    return discover_llvm(),
           discover_wrappers(),
           discover_julia()
end

if realpath(joinpath(pwd(), PROGRAM_FILE)) == realpath(@__FILE__)
    llvms, wrappers, julia = discover()

    println("LLVM toolchains:")
    for llvm in llvms
        println("- ", llvm)
    end
    println()

    println("LLVM wrappers:")
    for wrapper in wrappers
        println("- ", wrapper)
    end
    println()

    println("Julia: $julia")
end
