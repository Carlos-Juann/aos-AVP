#!/usr/bin/env bash
# Parches que se aplican después de `repo sync` para que este Nova se instale JUNTO al Nova original
# (otro id de paquete, otros providers, otro sharedUserId) y quede firmado con la clave del fork.
# Falla con error si algún texto esperado no está: así un cambio en Nova no pasa desapercibido.
#
# uso: smbfix-patches.sh <carpeta-con-Video-y-MediaLib> <ruta-al-keystore>
set -euo pipefail

ROOT="${1:?uso: smbfix-patches.sh <carpeta-nova> <keystore>}"
KEYSTORE="$(readlink -f "${2:?falta la ruta al keystore}")"

replace() { # archivo, texto viejo, texto nuevo (literales, en todas las apariciones)
  local file="$1" old="$2" new="$3"
  [ -f "$file" ] || { echo "ERROR: no existe $file" >&2; exit 1; }
  grep -qF -- "$old" "$file" || { echo "ERROR: no se encontró '$old' en $file" >&2; exit 1; }
  python3 - "$file" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1:4]
with open(path, encoding="utf-8") as f:
    s = f.read()
with open(path, "w", encoding="utf-8") as f:
    f.write(s.replace(old, new))
PY
  if grep -qF -- "$old" "$file"; then echo "ERROR: '$old' sigue presente en $file" >&2; exit 1; fi
  echo "ok: $file  [$old -> $new]"
}

VIDEO="$ROOT/Video"
MEDIALIB="$ROOT/MediaLib"

# 1) id del paquete distinto del Nova instalado (org.courville.nova)
replace "$VIDEO/build.gradle" 'applicationId = "org.courville.nova"' 'applicationId = "org.courville.nova.smbfix"'

# 2) FileProvider: el código tenía el id fijo; usar el del paquete en ejecución
replace "$VIDEO/src/main/java/com/archos/mediacenter/video/utils/PlayUtils.java" \
  '"org.courville.nova.provider"' 'context.getApplicationContext().getPackageName() + ".provider"'

# 3) providers con authority fija: dos apps no pueden compartirla (INSTALL_FAILED_CONFLICTING_PROVIDER)
replace "$VIDEO/AndroidManifest.xml" 'com.archos.media.videocommunity' 'com.archos.media.videosmbfix'
replace "$VIDEO/AndroidManifest.xml" 'com.archos.media.scrapercommunity' 'com.archos.media.scrapersmbfix'
replace "$VIDEO/AndroidManifest.xml" 'browser.SearchProviderVideocommunity' 'browser.SearchProviderVideosmbfix'
replace "$VIDEO/res/xml/searchable_video.xml" 'browser.SearchProviderVideocommunity' 'browser.SearchProviderVideosmbfix'
replace "$MEDIALIB/src/com/archos/mediaprovider/ArchosMediaCommon.java" 'com.archos.media.videocommunity' 'com.archos.media.videosmbfix'
replace "$MEDIALIB/src/com/archos/mediaprovider/ArchosMediaCommon.java" 'com.archos.media.scrapercommunity' 'com.archos.media.scrapersmbfix'

# 4) sharedUserId: apps con el mismo valor deben tener la misma firma; la nuestra se firma con otra clave
replace "$VIDEO/AndroidManifest.xml" 'android:sharedUserId="archos.openmediacenter"' 'android:sharedUserId="archos.openmediacenter.smbfix"'

# 4b) logs: smbj en DEBUG en el log por defecto (Android/data/<paquete>/files/logback/debug.log)
replace "$VIDEO/res/raw/logback_full.xml" '<logger name="com.archos.filecorelibrary.smbj" level="INFO"/>' '<logger name="com.archos.filecorelibrary.smbj" level="DEBUG"/>'
replace "$VIDEO/res/raw/logback_full.xml" '<logger name="com.hierynomus.smbj" level="INFO"/>' '<logger name="com.hierynomus.smbj" level="DEBUG"/>'

# 5) firma: el build de release solo firma si existe keystore.properties
cat > "$VIDEO/keystore.properties" <<EOF
storeFile=$KEYSTORE
storePassword=smbfix-nova
keyAlias=smbfix
keyPassword=smbfix-nova
EOF
echo "ok: keystore.properties escrito (storeFile=$KEYSTORE)"
