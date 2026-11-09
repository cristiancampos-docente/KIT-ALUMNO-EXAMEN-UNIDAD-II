#!/usr/bin/env bash
# Examen práctico Unidad II — PrestaLab UTEZ: verificación de capas y cableado
#
#   bash verificar_examen.sh
#
# Se corre desde la raíz de prestalab/ (o desde la carpeta que lo contiene).
# Revisa que las capas estén separadas, que MVVM y provider estén cableados
# como se pidió y que exista exactamente UNA prueba. No revisa que la app
# funcione: eso lo prueba el docente con su propia batería.
#
# NO EDITAR: el docente vuelve a correr una copia limpia de este archivo.
#
# Si el archivo llegó con saltos de línea de Windows (CRLF), se corre una copia limpia. Esta línea debe terminar en "#".
if grep -q $'\r' "$0" 2>/dev/null; then d=$(cd "$(dirname "$0")" && pwd); limpio="${TMPDIR:-/tmp}/verificar_examen_lf.sh"; tr -d '\r' < "$0" > "$limpio"; VERIFICAR_DIR="$d" exec bash "$limpio" "$@"; fi #

aqui="${VERIFICAR_DIR:-$(cd "$(dirname "$0")" && pwd)}"

proyecto=""
for candidato in "$1" "$aqui" "$aqui/prestalab" "$PWD" "$PWD/prestalab"; do
  [ -n "$candidato" ] || continue
  if [ -f "$candidato/pubspec.yaml" ] && grep -q "^name: prestalab" "$candidato/pubspec.yaml"; then
    proyecto="$candidato"
    break
  fi
done

if [ -z "$proyecto" ]; then
  echo "No encuentro el proyecto prestalab (falta pubspec.yaml con name: prestalab)."
  echo "Copia este script a la raíz de prestalab/ y córrelo desde ahí."
  exit 1
fi

cd "$proyecto" || exit 1
echo "Proyecto: $proyecto"

fallas=0

ok()    { echo "  OK     $1"; }
falta() { echo "  FALTA  $1"; fallas=$((fallas + 1)); }

# Solo cuentan las líneas import, no los comentarios que mencionan el paquete.
importa() { grep -rqnE "^[[:space:]]*import[[:space:]]+['\"].*$1" "$2"; }
# Código del archivo sin las líneas que son solo comentario.
codigo() { grep -vE "^[[:space:]]*//" "$1"; }
# true si el código (sin comentarios) contiene el patrón.
usa() { codigo "$2" | grep -qE "$1"; }

dom=lib/dominio/prestamo.dart
contrato=lib/datos/prestamo_repository.dart
memoria=lib/datos/memoria_prestamo_repository.dart
vm=lib/presentacion/prestamos_view_model.dart
lista=lib/presentacion/prestamos_page.dart
form=lib/presentacion/nuevo_prestamo_page.dart
main=lib/main.dart

echo
echo "1) Archivos del contrato"
for f in "$dom" "$contrato" "$memoria" "$vm" "$lista" "$form" "$main"; do
  if [ -f "$f" ]; then ok "$f"; else falta "$f no existe"; fi
done
if grep -qE "^[[:space:]]+provider:" pubspec.yaml; then ok "pubspec.yaml tiene provider"; else falta "pubspec.yaml no tiene provider en dependencies"; fi

echo
echo "2) Dominio y datos no conocen Flutter"
for capa in lib/dominio lib/datos; do
  if [ -d "$capa" ] && ! importa "package:flutter" "$capa"; then
    ok "$capa no importa package:flutter"
  else
    falta "$capa no existe o importa package:flutter"
  fi
done
if [ -f "$contrato" ] && usa "abstract[[:space:]]+(interface[[:space:]]+)?class[[:space:]]+PrestamoRepository" "$contrato"; then
  ok "PrestamoRepository es un contrato abstracto"
else
  falta "PrestamoRepository no es abstract class"
fi
if [ -f "$memoria" ] && usa "implements[[:space:]]+PrestamoRepository" "$memoria"; then
  ok "MemoriaPrestamoRepository implementa el contrato"
else
  falta "MemoriaPrestamoRepository no implementa PrestamoRepository"
fi

echo
echo "3) ViewModel: avisa, no dibuja, no sabe de dónde salen los datos"
if [ -f "$vm" ]; then
  if importa "material.dart" "$vm"; then falta "$vm importa material.dart (usa foundation.dart)"; else ok "$vm no importa material.dart"; fi
  if importa "provider" "$vm"; then falta "$vm importa provider: el ViewModel no debe saber quién lo entrega"; else ok "$vm no depende de provider"; fi
  if usa "extends[[:space:]]+ChangeNotifier" "$vm"; then ok "PrestamosViewModel extiende ChangeNotifier"; else falta "PrestamosViewModel no extiende ChangeNotifier"; fi
  if usa "notifyListeners\(\)" "$vm"; then ok "$vm llama a notifyListeners()"; else falta "$vm nunca llama a notifyListeners()"; fi
  if usa "MemoriaPrestamoRepository|memoria_prestamo" "$vm"; then falta "$vm conoce la implementación en memoria"; else ok "$vm solo conoce el contrato PrestamoRepository"; fi
  if usa "validarMatricula" "$vm" && usa "validarHoras" "$vm"; then ok "$vm usa las reglas del dominio"; else falta "$vm no llama a validarMatricula y validarHoras"; fi
  if usa "get[[:space:]]+totalHoras" "$vm"; then ok "totalHoras es estado derivado (getter)"; else falta "totalHoras debe ser un getter calculado"; fi
else
  falta "$vm no existe"
fi

echo
echo "4) Vistas: provider (watch para mostrar, read para actuar)"
for v in "$lista" "$form"; do
  [ -f "$v" ] || { falta "$v no existe"; continue; }
  if importa "package:provider" "$v"; then ok "$v importa provider"; else falta "$v no importa package:provider"; fi
  if usa "context\.watch<PrestamosViewModel>" "$v"; then ok "$v muestra con context.watch"; else falta "$v no usa context.watch<PrestamosViewModel>"; fi
  if usa "context\.read<PrestamosViewModel>" "$v"; then ok "$v actúa con context.read"; else falta "$v no usa context.read<PrestamosViewModel>"; fi
  if importa "datos/" "$v"; then falta "$v importa algo de lib/datos"; else ok "$v no importa nada de lib/datos"; fi
  if usa "required[[:space:]]+this\.(vm|viewModel)|ListenableBuilder" "$v"; then falta "$v recibe o escucha el ViewModel a mano"; else ok "$v pide el ViewModel al árbol"; fi
done
malos=$(grep -rnE "(on[A-Z][A-Za-z]*)[[:space:]]*:.*\.watch|\(\)[[:space:]]*(async[[:space:]]*)?=>.*\.watch" lib/presentacion 2>/dev/null \
  | grep -vE "^[^:]+:[0-9]+:[[:space:]]*//")
if [ -z "$malos" ]; then
  ok "ningún callback usa watch"
else
  while IFS= read -r m; do falta "watch dentro de un callback: $m"; done <<< "$malos"
fi

echo
echo "5) Navegación"
if [ -f "$lista" ] && usa "Navigator\.(of\(context\)\.)?push" "$lista" && usa "NuevoPrestamoPage" "$lista"; then
  ok "$lista abre NuevoPrestamoPage con Navigator.push"
else
  falta "$lista no hace Navigator.push a NuevoPrestamoPage"
fi
if [ -f "$form" ] && usa "Navigator\.(of\(context\)\.)?pop" "$form"; then
  ok "$form regresa con Navigator.pop"
else
  falta "$form no hace Navigator.pop"
fi
if [ -f "$form" ] && usa "void[[:space:]]+dispose\(\)" "$form"; then ok "$form libera sus controladores en dispose()"; else falta "$form no tiene dispose()"; fi

echo
echo "6) main.dart arma la app"
if [ -f "$main" ] && usa "ChangeNotifierProvider" "$main"; then ok "$main cuelga el ViewModel con ChangeNotifierProvider"; else falta "$main no usa ChangeNotifierProvider"; fi
if [ -f "$main" ] && usa "class[[:space:]]+PrestaLabApp" "$main"; then ok "$main define PrestaLabApp"; else falta "$main no define PrestaLabApp"; fi
intrusos=$(grep -rlE "^[[:space:]]*import[[:space:]]+['\"].*memoria_prestamo_repository" lib 2>/dev/null \
  | grep -vE "lib/main\.dart$")
if [ -z "$intrusos" ]; then
  ok "MemoriaPrestamoRepository solo se importa en main.dart"
else
  for i in $intrusos; do falta "$i importa la implementación en memoria"; done
fi

echo
echo "7) Exactamente UNA prueba"
pruebas=0
if [ -d test ]; then
  # test/_calificacion es la batería del docente; no cuenta.
  pruebas=$(grep -rhE "^[[:space:]]*(test|testWidgets)[[:space:]]*\(" test \
    --include="*.dart" --exclude-dir=_calificacion 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "$pruebas" -eq 1 ]; then
  ok "hay exactamente 1 prueba en test/"
else
  falta "se esperaba 1 prueba en test/ y hay $pruebas"
fi
if [ -f test/prestamos_view_model_test.dart ]; then ok "test/prestamos_view_model_test.dart existe"; else falta "test/prestamos_view_model_test.dart no existe"; fi

echo
if [ "$fallas" -eq 0 ]; then
  echo "Resultado: todo OK. Ahora corre: flutter test"
  exit 0
else
  echo "Resultado: $fallas punto(s) en FALTA."
  exit 1
fi
