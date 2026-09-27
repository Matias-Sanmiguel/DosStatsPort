# DIS Estadistica para Linux

DosStatsPort ejecuta los programas DOS `DIS.EXE`, `INVDIS.EXE` y
`GRAFDIS.EXE` en Linux x86_64 mediante una copia autocontenida de DOSBox
Staging. El build produce un AppImage y un bundle portable `tar.xz`.

> [!IMPORTANT]
> Este repositorio no incluye ni distribuye los ejecutables de DIS. Cada
> usuario debe aportar localmente una copia autorizada del ZIP original.
> Los ZIP, ejecutables DOS y artefactos generados estan excluidos de Git.

## Bring your own copy

El repositorio publico contiene solamente el launcher, la configuracion, las
pruebas y el builder. Al construir, `--input` recibe la copia local de DIS,
valida sus tres ejecutables contra `metadata/payload.sha256` y recien entonces
genera los bundles en `dist/`.

No se publican binarios preconstruidos en GitHub Releases porque contendrian
DIS. Cada usuario genera su propio AppImage o `tar.xz` en su equipo.

## Requisitos

- Linux x86_64.
- El ZIP original de la facultad, ya sea `DIS.zip` o el ZIP exterior que lo
  contiene.
- Para construir: Bash, `curl`, `file`, `install`, `sha256sum`, `tar`,
  `unzip` y `xz`.
- Para ejecutar: `flock` y `sha256sum`. El AppImage puede requerir FUSE en
  algunas distribuciones.

## Construccion

```sh
./scripts/build-linux.sh --input /ruta/al/paquete.zip
```

Los resultados se escriben en `dist/`:

- `DIS-Estadistica-0.1.0-linux-x86_64.AppImage`
- `DIS-Estadistica-0.1.0-linux-x86_64.tar.xz`
- `SHA256SUMS`
- `compliance/`, con fuentes y licencias de terceros

Para omitir el AppImage:

```sh
./scripts/build-linux.sh --input /ruta/al/paquete.zip --skip-appimage
```

El builder valida que el ZIP contenga solamente los tres ejecutables DOS y
que sus hashes coincidan con `metadata/payload.sha256`. Las descargas de
DOSBox Staging, appimagetool y el runtime AppImage tambien tienen checksums
fijados en `scripts/build-linux.sh`.

## Ejecucion

AppImage:

```sh
chmod +x dist/DIS-Estadistica-0.1.0-linux-x86_64.AppImage
./dist/DIS-Estadistica-0.1.0-linux-x86_64.AppImage
```

Si FUSE no esta disponible:

```sh
APPIMAGE_EXTRACT_AND_RUN=1 ./dist/DIS-Estadistica-0.1.0-linux-x86_64.AppImage
```

Bundle portable:

```sh
tar -xJf dist/DIS-Estadistica-0.1.0-linux-x86_64.tar.xz
./DIS-Estadistica-0.1.0-linux-x86_64/run.sh
```

El launcher acepta las siguientes opciones:

```text
--prepare-only      Prepara y valida el disco C sin abrir DOSBox.
--repair            Restaura los ejecutables administrados y guarda un backup.
--reset-data        Elimina los datos y la configuracion de la aplicacion.
--yes               Confirma --reset-data sin interaccion.
--allow-downgrade   Permite instalar un payload anterior.
--version           Muestra la version.
```

## Datos y preferencias

La aplicacion no escribe dentro del AppImage ni del bundle. Usa los
directorios XDG:

- Datos y disco C: `${XDG_DATA_HOME:-~/.local/share}/dis-estadistica`
- Preferencias: `${XDG_CONFIG_HOME:-~/.config}/dis-estadistica`
- Capturas y estado: `${XDG_STATE_HOME:-~/.local/state}/dis-estadistica`

El archivo opcional `settings.conf` del directorio de preferencias admite:

```ini
fullscreen=off
window_size=large
keyboard_layout=la 850
```

Los valores permitidos son `on`/`off` para `fullscreen`,
`default`/`small`/`medium`/`large` para `window_size`, y `auto`, `la`,
`la 850`, `sp` o `sp 850` para `keyboard_layout`.

Una sesion mantiene un lock exclusivo. Las actualizaciones conservan archivos
desconocidos creados por el usuario y usan un journal y un backup para poder
recuperarse de una interrupcion.

## Verificacion

```sh
./scripts/test.sh
sha256sum --check dist/SHA256SUMS
desktop-file-validate packaging/io.github.cauchothegaucho.DosStatsPort.desktop
appstreamcli validate --no-net packaging/io.github.cauchothegaucho.DosStatsPort.appdata.xml
```

## Licencias y distribucion

El launcher y los archivos propios de DosStatsPort se publican bajo MIT; vea
`LICENSE`. DOSBox Staging y sus componentes conservan sus propias licencias,
incluidas en cada bundle y en `dist/compliance/`. El codigo fuente
correspondiente a la version empaquetada de DOSBox Staging tambien se copia a
`dist/compliance/`.

Los ejecutables de DIS no forman parte del codigo MIT de este repositorio. El
builder los toma del ZIP suministrado por la facultad. Los artefactos que los
contienen son para uso personal y no deben redistribuirse sin autorizacion.
