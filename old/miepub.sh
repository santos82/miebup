#!/bin/bash

TMP=$(mktemp -d)
SCP=$(dirname $(realpath "$0"))
DIR=$(pwd)
PORTADA="$DIR/portada.jpg"

ASCII_ID=1

if [[ -f $1 ]]; then
	IN="$1"
else
	IN=`ls *.md | head -n 1`
	if [ -z "$IN" ]; then
		echo "Markdown no encontrado"
		exit 1
	fi
fi

echo "Convirtiendo $IN"

if [[ -z $2 ]]; then
	EPUB=`echo $IN | sed 's/\.[^\.]*$/\.epub/'`
else
	EPUB="$2"
fi

cp "$IN" "$TMP"

NT=0
if [[ $IN == *.md ]]; then
	TMD="$TMP/$IN"
	sed -r 's/^([\t ]*)[ivxdlcm]+\. /\1#. /i' -i "$TMD"
	sed -r 's/^([\t ]*[A-Z])\. /\1) /i' -i "$TMD"
	sed -r 's/^([1-9]+[0-9]*)\) /\1\\) /' -i "$TMD"

	if grep --quiet "\[\^1\]" "$TMD"; then
		NT=1
		if ! grep --quiet "^# Notas" "$TMD"; then
			echo "" >> "$TMD"
			echo "# Notas" >> "$TMD"
			echo "" >> "$TMD"
		fi
	fi

	if [ -f "~/.pandoc/epub.css" ]; then
		cp ~/.pandoc/epub.css ~/.pandoc/epub.css.bak
	fi

	if [ -f "$DIR/epub.css" ]; then
		cp "$DIR/epub.css" ~/.pandoc/
	elif [ -f "$SCP/epub.css" ]; then
		cp "$SCP/epub.css" ~/.pandoc/
	fi

	echo "Ejecutando pandoc"
	
	ASCII_ID=0
	if [ -f "$PORTADA" ]; then
		pandoc -S --toc-depth=2 --from markdown+ascii_identifiers --epub-cover-image="$PORTADA" -o "$TMP/$EPUB" "$TMD"
	else
		pandoc -S --toc-depth=2 --from markdown+ascii_identifiers -o "$TMP/$EPUB" "$TMD"
	fi

	if [ -f "~/.pandoc/epub.css.bak" ]; then
		cp ~/.pandoc/epub.css.bak ~/.pandoc/epub.css
		rm ~/.pandoc/epub.css.bak
	fi
else
	sed -e '/<meta[^>]*name="DC\..*/!d' -e 's/.*content="\([^"]*\).*name="DC\.\([^"]*\).*/<dc:\2>\1<\/dc:\2>/' "$IN" > "$TMP/metadata.xml"

	if [ ! -f "$PORTADA" ]; then
		PORTADA=$(grep -ohP "<meta[^>]+>" "$IN" | sed -e '/og:image/!d' -e 's/.*content="\([^"]*\)".*/\1/')
		if [[ $PORTADA == http* ]]; then
			wget "$PORTADA" --quiet --directory-prefix="$TMP"
			PORTADA="$TMP/${PORTADA##*/}"
		elif [ -f "$DIR/$PORTADA" ]; then
			$PORTADA="$DIR/$PORTADA"
		fi
	fi

	echo "Ejecutando pandoc"
	if [ -f "$PORTADA" ]; then
		pandoc --parse-raw --toc-depth=2 --epub-cover-image="$PORTADA" -o "$TMP/$EPUB" --epub-metadata="$TMP/metadata.xml" "$IN"
	else
		pandoc --parse-raw --toc-depth=2 -o "$TMP/$EPUB" --epub-metadata="$TMP/metadata.xml" "$IN"
	fi
fi

cd "$TMP"

find . -type f -not -name "$EPUB" -delete

unzip -q "$EPUB"

rm "$EPUB"

rm nav.xhtml
rm title_page.xhtml

sed '/<item id="nav" /d' -i content.opf
sed '/<item id="title_page" /d' -i content.opf
sed '/<item id="title_page_xhtml" /d' -i content.opf
sed '/<itemref idref="title_page" /d' -i content.opf
sed '/<itemref idref="title_page_xhtml" /d' -i content.opf
sed '/<itemref idref="nav" /d' -i content.opf
sed '/href="nav.xhtml"/d' -i content.opf
perl -0777 -pe 's/\s*<navPoint id=.navPoint-0.>\s*<navLabel>\s*<text>.*?\s*<\/navLabel>\s*<content src="title_page.xhtml" \/>\s*<\/navPoint>//igs' -i toc.ncx

if [ $ASCII_ID -eq 1 ]; then
	echo "Limpiando identificadores"
	perl -ple 'sub clean{ my ($s)=@_; $s =~ s/[^[:ascii:]]/-/g; return $s;}; s/#([^"]+)/"#" . clean($1)/e' -i toc.ncx
	perl -ple 'sub clean{ my ($s)=@_; $s =~ s/[^[:ascii:]]/-/g; return $s;}; s/<div id="([^"]+)/"<div id=\"" . clean($1)/ge' -i ch00*.xhtml
fi

if [ $NT -eq 1 ]; then
	echo "Generando notas"
	python "$SCP/notas.py"
fi

unmb=`expr 1024 \* 1024`
list=`find . -type f -regextype posix-extended -regex '.*\.(jpg|png|jpeg)'`
length=`echo "$list" | sed '/^$/d' | wc -l`
if [ $length -ne 0 ]; then
    echo "$length imagenes encontradas"
    antes=$(expr $(echo "$(stat --printf="%s + " $list) 0"))
    echo "Eliminando metadatos"
    exiftool -r -overwrite_original -q -all= .
    ahora=$(expr $(echo "$(stat --printf="%s + " $list) 0"))
    difkbmeta=`expr $antes - $ahora`
    difkbmeta=`expr $difkbmeta / 1024`
    echo "$difkbmeta KB ahorrados"
    count=0
    difkb=0
    for file in $list; do
        cp "$file" "$file.ori"
        antes=`stat --printf="%s" "$file"`
        ancho_antes=`identify -format "%w" "$file"`
        alto_antes=`identify -format "%h" "$file"`
        mogrify -strip +repage -trim -fuzz 600 "$file"
        picopt --quiet --destroy_metadata --comics --enable_advpng "$file"
        despues=`stat --printf="%s" "$file"`

        if [ "$despues" -gt 2097152 ]; then
            #Imagenes de mas de dos megas
            cp "$file.ori" "$file"
            mogrify -strip +repage -trim -fuzz 600 -resize 40% -quality 70 "$file"
            picopt --quiet --destroy_metadata --comics --enable_advpng "$file"
        elif [ "$despues" -gt 1048576 ]; then
            #Imagenes de mas de un mega
            cp "$file.ori" "$file"
            mogrify -strip +repage -trim -fuzz 600 -resize 50% -quality 75 "$file"
            picopt --quiet --destroy_metadata --comics --enable_advpng "$file"
        fi
        despues=`stat --printf="%s" "$file"`
        ancho_despues=`identify -format "%w" "$file"`
        alto_despues=`identify -format "%h" "$file"`
        differencia=`expr $antes - $despues`
        
        differencia_alto=`expr $alto_antes - $alto_despues`
        differencia_ancho=`expr $ancho_antes - $ancho_despues`

        if [ "$differencia_alto" -gt 15 ] || [ "$differencia_ancho" -gt 17 ] || [ "$differencia" -gt 15 ]; then
            #echo "$file pasa de $ancho_antes x $alto_antes a $ancho_despues x $alto_despues ($differencia bytes menos)"
            count=`expr $count + 1`
            difkb=`expr $difkb + $differencia`
            nombre=$(basename "$file")
            extension="${nombre##*.}"
            nombre="${EPUB}-${nombre%.*}"
            #cp "$file.ori" "cmp/$nombre.0.$extension"
            #cp "$file" "cmp/$nombre.1.$extension"
        else
            #cp "$file.ori" "cmp/$nombre.2.$extension"
            cp "$file.ori" "$file"
        fi
        rm "$file.ori"
    done
    difkb=`expr $difkb / 1024`
    echo "$count imagenes retocadas, $difkb KB ahorrados"
    difkb=`expr $difkbmeta + $difkb`
    difmb=`expr $difkb / 1024`
    echo "En total, se reduce $difmb MB"
fi

zip -r -q "$EPUB" *
cp "$EPUB" "$DIR/$EPUB"

echo "$EPUB creado"
