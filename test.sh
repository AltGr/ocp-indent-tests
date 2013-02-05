#!/bin/bash -ue

mkdir -p orig

sources=()
names=()
urls=()
configs=()

while read name url config; do
    if [ $# -eq 0 ] || [[ "$*" =~ "$name" ]]; then
        names+=("$name")
        urls+=("$url")
        configs+=("$config")
    fi
done < sources

for ((i=0; i<${#names[@]}; i++)); do
    url=${urls[i]}
    name=${names[i]}
    if ! [ -d "orig/$name" ]; then
        echo "Downloading $name";
        mkdir -p "orig/$name"
        cd "orig/$name"
        wget "$url"
        tgz=$(ls)
        tar -xzf "$tgz"
        find . ! -type d ! -name \*.ml ! -name \*.mli -delete
        find . -empty -delete
        cd -
    fi
done

indent-all() {
    local indent=$1; shift
    local destdir=$1; shift
    [ $# -eq 0 ]
    for ((i=0; i<${#names[@]}; i++)); do
        local name=${names[i]}
        local config=${configs[i]}
        echo -n "Indenting all source from $name... " >&2
        for f in $(find orig/$name ! -type d); do
            local dest=$destdir/${f#orig/}
            mkdir -p $(dirname $dest)
            $indent "$f" $config > "$dest"
        done
        echo "done" >&2
    done
}

echo "=== Indentation with tuareg ===" >&2
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
    local config=$(ocp-config-to-tuareg "$@")
    emacs $f -q -batch --eval '(progn (tuareg-mode) '$config' (indent-region (point-min) (point-max)) (set-visited-file-name "'/dev/stdout'") (save-buffer 0))' 2>/dev/null || true
}
indent-all tuareg-indent tuareg
echo >&2

echo "=== Indentation with ocp-indent ===" >&2
indent-all ocp-indent new
echo >&2

# diff -y --suppress-common-lines -E "$1" "$2" |wc -l

diffcount() {
    [ $# -eq 2 ]

    local origindent=$(mktemp /tmp/orig-indent.XXXXX)

    awk -F'[^ ]' '{ print length($1) }' $1 >$origindent
    awk -F'[^ ]' '{ print length($1) }' $2 \
        | paste $origindent - \
        | awk '{ diff = $2 - $1;
                 if (diff && diff != last) tot++;
                 last = diff }
               END { print (tot+0) }'

    rm -f $origindent
}

version=$(ocp-indent --version | grep version)
cat <<EOF >status.html
<html><head><title>
Status of $version
</title>
<style>
body { background-color: white; color: grey; font-family: monospace; text-align: center}
table { margin: auto; }
th { margin: 0; padding: 12px 5px; text-align: left; }
td { margin: 0; padding: 12px 5px; text-align: center; }
.bar { border-left: 1px solid black }
</style></head><body>
<h2>Status of $version on various projects</h2>

<p>Ratio of correctly indented lines (compared to the line above)</p>
<br>
<table>
<tr><th><th colspan=2 class=bar>tuareg<th colspan=2 class=bar>ocp-indent</tr>
EOF

printf "Blocks indented differently compared to number of lines:\n\n"
printf "\e[34m%-15s  %15s  %15s  %15s  %15s  %15s\e[m\n" \
    source tuareg/orig current/orig new/current new/orig progression

for name in ${names[@]}; do
    if ! [ -d current/$name ]; then
        cp -r new/$name current
    fi
    total=0; to=0; co=0; no=0; nc=0
    for f in $(find orig/$name ! -type d); do
        f=${f#orig/}
        total=$((total + $(wc -l <orig/$f)))
        to=$((to + $(diffcount tuareg/$f orig/$f)))
        co=$((co + $(diffcount current/$f orig/$f)))
        nc=$((nc + $(diffcount new/$f current/$f)))
        no=$((no + $(diffcount new/$f orig/$f)))
    done
    printf "\e[34m%-15s\e[m  %14d%%  %14d%%  %14d%%  %14d%%  \e[%dm%+15d\e[m\n" \
        $name $((to*100/total)) $((co*100/total)) $((nc*100/total)) $((no*100/total)) \
        $(if [ $no -eq $co ]; then echo 33
        elif [ $no -gt $co ]; then echo 31
        else echo 32; fi) \
        $((co - no))
    printf "<tr><th>%s<td class=bar>%d / %d<td>%d.%d<td class=bar>%d / %d<td>%d.%d</tr>\n" \
        $name \
        $((total - to)) $total $(((total - to)*100/total)) $(((total - to)*10000/total % 100)) \
        $((total - no)) $total $(((total - no)*100/total)) $(((total - no)*10000/total % 100)) \
        >>status.html
done

cat <<EOF >>status.html
</table>
</body>
</html>
EOF
