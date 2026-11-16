# inf2md.awk - fpGUI richtext (from `inf2txt -l`) -> GitHub-flavoured markdown. Run by inf2txt.sh --md.
#
# What the docview parser emits, and what each becomes:
#   "===<n>=== title"            topic line, <n> its contents level -> heading of level n (1-6; 0 = not in the
#                                 contents -> level 6)
#   <nowrap> ... </nowrap>       preformatted text (examples, box-drawn tables) -> fenced code block, verbatim
#   <b> <i>                      emphasis openers -> ** and *
#   </i></b></u></color>         the parser closes every span with this one bundle, whatever it opened, so the
#                                 closers are matched against what is actually open (a stack), never mapped 1:1
#   <tt>, <font "..." N>         monospace -> inline code, closed by </tt> / </font>
#   << and >>                    a literal "<" / ">" in the book's text (#include <<netcons.h>>; fpGUI
#                                 RichTextDocumentUnit.pas, the "<"/">" arms of its element scanner)
#   BEL at a line's start        a list bullet -> "- "
#   everything else              <leftmargin>, <color>, <link>, <align>, <u> ... layout only: dropped, text kept
# Text outside code is escaped where markdown would read it as markup.

function lit(s) { gsub(/>>/, ">", s); return s }
function esc(s) {
    s = lit(s)
    gsub(/\\/, "\\\\", s); gsub(/\*/, "\\*", s); gsub(/_/, "\\_", s); gsub(/`/, "\\`", s)
    gsub(/\[/, "\\[", s); gsub(/\]/, "\\]", s); gsub(/</, "\\<", s)
    return s
}
# Close every open emphasis, keeping trailing blanks outside the delimiter (GFM will not close "**x **").
function closeall(   sp) {
    if (mono) endmono()
    if (depth == 0) return
    match(out, /[ \t]+$/); sp = (RSTART ? substr(out, RSTART) : ""); if (RSTART) out = substr(out, 1, RSTART - 1)
    while (depth > 0) out = out stk[depth--]
    out = out sp
}
# Close inline code: an empty span is dropped, trailing blanks go outside the backtick.
function endmono(   sp) {
    mono = 0
    if (substr(out, length(out)) == "`") { out = substr(out, 1, length(out) - 1); return }
    match(out, /[ \t]+$/); sp = (RSTART ? substr(out, RSTART) : ""); if (RSTART) out = substr(out, 1, RSTART - 1)
    out = out "`" sp
}
function heading(lv, title) {
    if (lv < 1 || lv > 6) lv = 6
    return substr("######", 1, lv) " " esc(title)
}
BEGIN { inpre = 0; depth = 0; mono = 0 }
{
    line = $0
    if (!inpre && match(line, /^===[0-9]+=== /)) {
        closeall(); if (out != "") { print out; out = "" }
        lv = substr(line, 4, RLENGTH - 7) + 0
        print ""; print heading(lv, substr(line, RLENGTH + 1)); print ""
        next
    }
    out = ""
    if (!inpre && substr(line, 1, 1) == "\007") { out = "- "; line = substr(line, 2) }
    while (line != "") {
        if (inpre) {
            p = index(line, "</nowrap>")
            seg = (p ? substr(line, 1, p - 1) : line)
            gsub(/<<|<[^<>]*>/, "&\001", seg)            # mark tags, then drop them; keep "<<" as "<"
            gsub(/<<\001/, "<", seg); gsub(/<[^<>]*>\001/, "", seg); seg = lit(seg)
            out = out seg
            if (!p) { line = ""; break }
            out = out "\n```"; inpre = 0; line = substr(line, p + 9)
            continue
        }
        p = index(line, "<")
        if (!p) { out = out (mono ? lit(line) : esc(line)); break }
        pre = substr(line, 1, p - 1); out = out (mono ? lit(pre) : esc(pre)); line = substr(line, p)
        if (substr(line, 1, 2) == "<<") { out = out (mono ? "<" : "\\<"); line = substr(line, 3); continue }
        q = index(line, ">")
        if (!q) { out = out (mono ? lit(line) : esc(line)); break }
        tag = substr(line, 1, q); line = substr(line, q + 1)
        if (tag == "<nowrap>") {
            closeall(); out = out (out == "" ? "" : "\n") "```\n"; inpre = 1
        } else if (tag == "<b>" && !mono) {
            out = out "**"; stk[++depth] = "**"
        } else if (tag == "<i>" && !mono) {
            out = out "*"; stk[++depth] = "*"
        } else if (tag == "<tt>" || tag ~ /^<font /) {
            if (!mono) { out = out "`"; mono = 1 }
        } else if (tag == "</tt>" || tag == "</font>") {
            if (mono) endmono()
        } else if (tag == "</i>" || tag == "</b>") {
            if (depth > 0 && !mono) {
                match(out, /[ \t]+$/); sp = (RSTART ? substr(out, RSTART) : ""); if (RSTART) out = substr(out, 1, RSTART - 1)
                out = out stk[depth--] sp
            }
        }
    }
    if (!inpre && mono) endmono()     # inline code never spans lines in markdown
    if (!inpre && $0 ~ /^[ \t]*$/) closeall()          # a blank line ends a paragraph: no span crosses it
    if (!inpre && out ~ /^#/) out = "\\" out
    print out
}
END { closeall(); if (inpre) print "```" }
