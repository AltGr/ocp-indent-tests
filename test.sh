#!/bin/bash -ue

export LC_ALL=C
TIMEFORMAT=%R

mkdir -p orig

TESTROOT=$PWD
TASKS=()
PROJECTS=()

help() {
    cat <<EOF
Simple script to compare some indentation engines over a base of ocaml code.

Usage: $0 [tasks] [projects]

projects are patterns over source names as found in the sources file. By
default, all are processed.

Available tasks :
	download	Downloads the sources that aren't there already
	tuareg		Compute tuareg indentation to folder tuareg/
	ocp-update	Get and compile the latest version of ocp-indent
	ocp-indent	Compute ocp-indent indentation to folder new/
	report		Summarise differences between the different outputs
	html		Generates a file 'status.html' showing a table of
			results

If none supplied, will do "download tuareg ocp-indent report html"
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        download|tuareg|ocp-update|ocp-indent|report|html)
            TASKS+=($1);;
        help|-h|--help)
            help; exit 0;;
        *)
            PROJECTS+=("$1")
    esac
    shift
done

if [ ${#TASKS[@]} -eq 0 ]; then
    TASKS=(download tuareg ocp-indent report html)
fi

sources=()
names=()
urls=()
configs=()

while read name url config; do
    if [ ${#PROJECTS[@]} -eq 0 ] || [[ "${PROJECTS[*]}" =~ "$name" ]]; then
        names+=("$name")
        urls+=("$url")
        configs+=("$config")
    fi
done < sources

OCP_INDENT="$PWD/ocp-indent/ocp-indent"
if [[ "${TASKS[*]}" =~ "ocp-update" ]]; then
    echo "=== Get latest ocp-indent ==="
    rm -rf ocp-indent
    git clone git@github.com:OCamlPro/ocp-indent
    cd ocp-indent
    ./configure
    make
    cd "$TESTROOT"
    [ -x "$OCP_INDENT" ]
fi

if [ -x "$OCP_INDENT" ]; then
    ocp_indent_version="$(ocp-indent --version | grep version)\
@$(cd ocp-indent && git log -n1 --date=short --format="%h (%cd)")"
    echo "=> using local checkout of ocp-indent: $ocp_indent_version"
elif [ ! -x "$OCP_INDENT" ]; then
    OCP_INDENT=$(which ocp-indent)
    ocp_indent_version="$($OCP_INDENT --version | grep version)"
    echo "=> no local checkout of ocp-indent, using $ocp_indent_version from the system"
fi


if [[ "${TASKS[*]}" =~ "download" ]]; then
    echo "=== Downloading packages ===" >&2
    for ((i=0; i<${#names[@]}; i++)); do
        url=${urls[i]}
        name=${names[i]}
        if ! [ -d "orig/$name" ]; then
            echo -n "Downloading $name... ";
            mkdir -p "orig/$name"
            cd "orig/$name"
            wget --quiet "$url"
            echo -n "uncompressing... ";
            tgz=$(ls)
            case "$tgz" in
                *.tar.gz|*.tgz) tar -xzf "$tgz";;
                *.tar.bz2|*.tbz2) tar -xjf "$tgz";;
                *.zip) unzip "$tgz" >/dev/null;;
                *) echo "Unknown archive type $tgz, sorry."; exit 2;;
            esac
            echo -n "cleaning up... ";
            find . ! -type d ! -name \*.ml ! -name \*.mli -delete
            find . -empty -delete
            # replace tabs for easier comparison (but how many ??)
            find . ! -type d -exec sed -i 's/\t/  /g' {} \;
            echo "done";
            cd "$TESTROOT"
        fi
    done
    # This file in core is 30000 lines long with a huge expr. Tuareg chokes on
    # it, and it's not really representative
    rm -f "orig/core/*/lib_test/ofday_unit_tests_v1.ml"
fi

indent-all() {
    local indent=$1; shift
    local destdir=$1; shift
    [ $# -eq 0 ]
    mkdir -p "$destdir"
    for ((i=0; i<${#names[@]}; i++)); do
        local name=${names[i]}
        local config=${configs[i]}
        echo -n "Indenting all source from $name... " >&2
        time ( for f in $(find orig/$name ! -type d); do
            local dest=$destdir/${f#orig/}
            mkdir -p $(dirname $dest)
            $indent "$f" $config > "$dest"
        done ) 2>"$destdir/$name.time"
        printf "done in %.2fs\n" "$(cat "$destdir/$name.time")" >&2
    done
}


# === Indentation with tuareg ===

ocp-config-to-tuareg() {
    while [ $# -gt 0 ]; do
        case $1 in
            -c)
                shift
                local c="normal,$1"
                c=$(sed 's/normal/base=2,type=2,in=0,with=0,match_clause=2/' <<<"$c")
                c=$(sed 's/JaneStreet/base=2,type=0,in=0,with=0,match_clause=2/' <<<"$c")
                awk 'BEGIN { RS=","; FS="=" } { print $1,$2 }' <<<"$c" | {
                    while read var val; do
                        case "$var" in
                            "base")         echo "(setq tuareg-default-indent $val)";;
                            "type")         echo "(setq tuareg-type-indent $val)";;
                            "in")           echo "(setq tuareg-in-indent $val)";;
                            "with")         echo "(setq tuareg-with-indent $val)";;
                            "match_clause") echo "(setq tuareg-type-indent $val)";;
                            "") ;;
                            *)
                                echo "Error: config option not understood by tuareg conversion: '$var'" >&2
                        esac
                    done
                }
                ;;
            *)
                echo "Error: config parameter not understood by tuareg conversion: '$1'" >&2
        esac
        shift
    done
}
tuareg-indent() {
    local f=$1; shift
    local config=$(ocp-config-to-tuareg $*)
    local tuareg=$(ls /usr/share/emacs*/site-lisp/tuareg-mode/tuareg.elc 2>/dev/null \
                || ls /usr/share/emacs/site-lisp/tuareg-mode/tuareg.el)
    emacs $f -Q -batch --eval '(progn (load-file "'"$tuareg"'") (tuareg-mode) '"$config"' (setq indent-tabs-mode nil) (indent-region (point-min) (point-max)) (set-visited-file-name "'/dev/stdout'") (save-buffer 0))' 2>/dev/null || true
}
if [[ "${TASKS[*]}" =~ "tuareg" ]]; then
    echo "=== Indentation with tuareg ===" >&2
    indent-all tuareg-indent tuareg
    echo >&2
fi


# === Indentation with ocp-indent ===

ocp-indent-f() {
    local f=$1; shift
    /usr/bin/time -o time -a -f %e $OCP_INDENT $* $f
}
if [[ "${TASKS[*]}" =~ "ocp-indent" ]]; then
    echo "=== Indentation with ocp-indent ===" >&2
    indent-all ocp-indent-f new
    echo >&2
fi


# === Computation of diffs ===

# diff -y --suppress-common-lines -E "$1" "$2" |wc -l
diffcount() {
    [ $# -eq 2 ]

    local origindent=$(mktemp /tmp/orig-indent.XXXXX)

    awk -F'[^ \t].*' '{ gsub(/\t/,"        ",$1); print length($1) }' $1 >$origindent
    awk -F'[^ \t].*' '{ print length($1) }' $2 \
        | paste $origindent - \
        | awk '{ diff = $2 - $1;
                 if (diff && diff != last) tot++;
                 last = diff }
               END { print (tot+0) }'

    rm -f $origindent
}

if [[ "${TASKS[*]}" =~ "html" ]]; then
    cat <<EOF >status.html
<html><head><title>
Status of $ocp_indent_version
</title>
<style>
body { background-color: white; color: grey; font-family: monospace; text-align: center}
table { margin: auto; }
th { padding: 12px 8px; text-align: left; }
th.col { text-align: center; }
td { padding: 12px 8px; text-align: center; }
.bar { border-bottom: 1px solid grey; }
.bold { font-weight: bold; }
</style></head><body>
<h2>Status of $ocp_indent_version</h2>

<p>Ratio of correctly indented lines (compared to the line above)</p>
<br>
<table>
<tr><th><th colspan=3 class=bar>tuareg<th colspan=3 class=bar>ocp-indent</tr>
<tr><th><th class=col>lines<th class=col>ratio<th class=col>time*
        <th class=col>lines<th class=col>ratio<th class=col>time</tr>
EOF
fi

if [[ "${TASKS[*]}" =~ "report" ]]; then
    printf "Blocks indented differently compared to number of lines:\n\n"
    printf "\e[34m%-15s  %15s  %15s  %15s  %15s  %15s\e[m\n" \
        source tuareg/orig current/orig new/current new/orig progression
fi

if [[ "${TASKS[*]}" =~ "report" ]] || [[ "${TASKS[*]}" =~ "html" ]]; then
for name in ${names[@]}; do
    if ! [ -d current/$name ]; then
        cp -r new/$name current
    fi
    total=0; to=0; co=0; no=0; nc=0
    for f in $(find orig/$name ! -type d); do
        f=${f#orig/}
        total=$((total + $(wc -l <orig/$f)))
        to=$((to + $(diffcount tuareg/$f orig/$f)))
        no=$((no + $(diffcount new/$f orig/$f)))
        if [[ "${TASKS[*]}" =~ "report" ]]; then
            co=$((co + $(diffcount current/$f orig/$f)))
            nc=$((nc + $(diffcount new/$f current/$f)))
        fi
    done
    if [[ "${TASKS[*]}" =~ "report" ]]; then
        printf "\e[34m%-15s\e[m  %14d%%  %14d%%  %14d%%  %14d%%  \e[%dm%+15d\e[m\n" \
            $name $((to*100/total)) $((co*100/total)) $((nc*100/total)) $((no*100/total)) \
            $(if [ $no -eq $co ]; then echo 33
              elif [ $no -gt $co ]; then echo 31
              else echo 32; fi) \
            $((co - no))
    fi
    if [[ "${TASKS[*]}" =~ "html" ]]; then
        printf "<tr><th>%s<td>%d / %d<td class=bold>%d.%d%%<td>%.2fs<td>%d / %d<td class=bold>%d.%d%%<td>%.2fs</tr>\n" \
            $name \
            $((total - to)) $total $(((total - to)*100/total)) $(((total - to)*10000/total % 100)) \
              $(cat tuareg/$name.time) \
            $((total - no)) $total $(((total - no)*100/total)) $(((total - no)*10000/total % 100)) \
              $(cat new/$name.time) \
            >>status.html
    fi
done
fi

if [[ "${TASKS[*]}" =~ "html" ]]; then
    cat <<EOF >>status.html
</table>

<p style="margin-top:8ex;"><small>* Tuareg times include emacs startup time for
each file (with the -Q option)</small></p>
</body>
</html>
EOF
fi
