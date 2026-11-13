#!/bin/sh
# usage: inf2txt.sh [--md] <path-to-inf>   -> clean UTF-8 plain text on stdout
#        --md: GitHub-flavoured markdown instead - headings from the contents levels, emphasis, inline code,
#              preformatted blocks fenced (inf2md.awk says what maps to what)
#
# The IPF text inside an .INF is stored in an IBM PC code page (CP850 for the
# OS/2 programming books; CP437 for some older material), NOT in UTF-8. Emitted
# raw, the high bytes make the output look like ISO-8859 to `file`, and GNU grep
# then classifies it as *binary* and silently prints nothing at all -- no error,
# no "binary file matches". A verification grep that returns empty is then read
# as "IBM does not document this", which is exactly backwards.
#
# So we transcode to UTF-8 here. Override the source code page with
# INF2TXT_CP=CP437 (etc.) if a book converts wrongly.
set -e
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

md=
[ "$1" = "--md" ] && { md=1; shift; }
[ $# -ge 1 ] || { echo "usage: inf2txt.sh [--md] <path-to-inf>" >&2; exit 2; }
[ -r "$1" ]  || { echo "inf2txt.sh: cannot read '$1'" >&2; exit 2; }
# The binary is built per user (build.sh / inf2txt-build) into $INF2TXT_HOME;
# a build left beside this script by an older checkout is still honoured.
: "${INF2TXT_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/os2-toolkit/inf2txt}"
if   [ -x "$INF2TXT_HOME/inf2txt" ]; then bin="$INF2TXT_HOME/inf2txt"
elif [ -x "$dir/inf2txt" ];          then bin="$dir/inf2txt"
else
    echo "inf2txt.sh: inf2txt not built - run inf2txt-build (or $dir/build.sh) first" >&2
    exit 127
fi

: "${INF2TXT_CP:=CP850}"

# Probe once, up front: a mid-pipeline fallback is not possible because the
# failing iconv would already have consumed stdin. -c drops any unconvertible
# byte rather than aborting, so a bad byte cannot silently truncate a book.
if command -v iconv >/dev/null 2>&1 &&
   printf '' | iconv -f "$INF2TXT_CP" -t UTF-8 >/dev/null 2>&1; then
    conv="iconv -c -f $INF2TXT_CP -t UTF-8//TRANSLIT"
else
    conv="cat"
    echo "inf2txt.sh: warning: iconv unavailable or '$INF2TXT_CP' unsupported;" >&2
    echo "  output stays in the source code page -- you MUST use 'grep -a'" >&2
fi

# Note: the exit status of this pipeline is the last stage's, not inf2txt's; the
# -x check above is the portable guard (set -o pipefail is not POSIX sh).
# The extractor also emits IPF control bytes that are not text: BEL (0x07) marks
# a list bullet, with a few other C0 codes scattered through. Left in, they make
# `file` call the output data and GNU grep treat it as binary -- the same silent
# empty-result failure the transcode above exists to prevent -- and they are not
# characters any reader wants. Dropped here; tab, newline and CR are kept.
if [ -n "$md" ]; then
    # The markdown mode needs the topic levels (`inf2txt -l`, from a build of this checkout's inf2txt.pas).
    "$bin" -l "$1" | head -1 | grep -q '^===[0-9]*=== ' || {
        echo "inf2txt.sh: --md needs an inf2txt built with -l - rerun inf2txt-build (or $dir/build.sh)" >&2
        exit 127
    }
    "$bin" -l "$1" \
     | LC_ALL=C awk -f "$dir/inf2md.awk" \
     | tr -d '\000-\010\013\014\016-\037' \
     | sed -E 's/[ \t]+$//' \
     | cat -s \
     | $conv
    exit 0
fi

"$bin" "$1" \
 | sed -E 's/<[^>]*>//g' \
 | tr -d '\000-\010\013\014\016-\037' \
 | sed -E 's/[ \t]+$//' \
 | cat -s \
 | $conv
