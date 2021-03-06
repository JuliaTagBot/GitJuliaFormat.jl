module GitJuliaFormat

println("Running DocumentFormat on modified lines!")

using DocumentFormat
using LibGit2

# ========== LibGit2 Extensions ==========================
# ----------------- Git Diff Foreach ---------------------

#= typedef int(*git_diff_binary_cb)(
	const git_diff_delta *delta,
	const git_diff_binary *binary,
	void *payload); =#
default_file_cb(delta::LibGit2.DiffDelta, _1, _2) = Int32(0)
default_binary_cb(delta::LibGit2.DiffDelta, _1, _2) = Int32(0)

# int git_diff_foreach(git_diff *diff, git_diff_file_cb file_cb, git_diff_binary_cb binary_cb, git_diff_hunk_cb hunk_cb, git_diff_line_cb line_cb, void *payload);
function git_diff_foreach(diff; file_cb = default_file_cb, binary_cb = default_binary_cb, hunk_cb = C_NULL, line_cb = C_NULL, payload = C_NULL)
    file_cb = @cfunction($file_cb, Cint, (Ref{LibGit2.DiffDelta}, Ptr{Cvoid}, Ptr{Cvoid}))
    binary_cb = @cfunction($binary_cb, Cint, (Ref{LibGit2.DiffDelta}, Ptr{Cvoid}, Ptr{Cvoid}))
    if hunk_cb != C_NULL
        hunk_cb = @cfunction($hunk_cb, Cint, (Ref{LibGit2.DiffDelta}, Ptr{Cvoid}, Ptr{Cvoid}))
    end
    if line_cb != C_NULL
        line_cb = @cfunction($line_cb, Cint, (Ref{LibGit2.DiffDelta}, Ptr{Cvoid}, Ptr{Cvoid}))
    end

    ccall((:git_diff_foreach, :libgit2), Cint,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
          diff.ptr, file_cb, binary_cb, hunk_cb, line_cb, payload)
end


# ----------------- Git Diff Hunk Callback ---------------

#define GIT_DIFF_HUNK_HEADER_SIZE	128
const GIT_DIFF_HUNK_HEADER_SIZE	= 128

struct GitDiffHunk
   	old_start::Cint     # /**< Starting line number in old_file */
   	old_lines::Cint     # /**< Number of lines in old_file */
   	new_start::Cint     # /**< Starting line number in new_file */
   	new_lines::Cint     # /**< Number of lines in new_file */
   	header_len::Csize_t    # /**< Number of bytes in header text */
   	header::NTuple{GIT_DIFF_HUNK_HEADER_SIZE,UInt8}   # /**< Header text, NUL-byte terminated */
end

# ========================================================

function document_format_diff_hunk(delta::LibGit2.DiffDelta,
        hunk_ptr::Ptr{Cvoid}, offsets_ptr::Ptr{Cvoid})

    new_filename = unsafe_string(delta.new_file.path)
    if match(r"\.jl$", new_filename) == nothing
        # Only format julia files
        return Int32(0)
    end

    offsets = unsafe_pointer_to_objref(offsets_ptr)

    hunk = unsafe_load(reinterpret(Ptr{GitJuliaFormat.GitDiffHunk}, hunk_ptr))
    # Print the header of the section being formatted.
    println(read(IOBuffer([hunk.header[1:hunk.header_len]...]), String))

    #old_file_lines = readlines(unsafe_string(delta.old_file.path))
    #println(old_file_lines[hunk.old_start : hunk.old_start+hunk.old_lines]...)

    new_file_lines = readlines(new_filename)

    hunk_start = hunk.new_start
    hunk_end = hunk_start + hunk.new_lines - 1

    if new_filename in keys(offsets)
        offset = offsets[new_filename]
    else
        offset = 0
    end
    hunk_start += offset
    hunk_end += offset

    toformat_lines = new_file_lines[hunk_start:hunk_end]
    toformat = join(new_file_lines[hunk_start:hunk_end], "\n")

    formatted = DocumentFormat.format(toformat)

    formatted_lines = split(formatted, "\n")

    added_lines = length(formatted_lines) - length(toformat_lines)
    if added_lines != 0
        offset += added_lines
        println(offset)
        offsets[new_filename] = offset
    end

    outlines = vcat(new_file_lines[1:hunk_start - 1], formatted_lines, new_file_lines[hunk_end + 1:end])

    write(new_filename, join(outlines, "\n"))

    return Int32(0)
end

function main(ARGS=Base.ARGS)
    # TODO: Read the commits and repo path from Base.ARGS
    r = LibGit2.init(".")
    prevtree = LibGit2.GitTree(r, "HEAD~^{tree}")
    headtree = LibGit2.GitTree(r, "HEAD^{tree}")
    diff = LibGit2.diff_tree(r, prevtree, headtree)
    delta = diff[1]

    git_diff_foreach(diff;
         hunk_cb = document_format_diff_hunk,
         payload = Ref(Dict{String,Int}()))
end

end
