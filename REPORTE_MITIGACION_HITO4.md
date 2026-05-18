# REPORTE TÉCNICO: MITIGACIÓN DE VULNERABILIDAD EN EL KERNEL (HITO 4)

## 1. Justificación del Entorno y del Uso de Código en C

El laboratorio se ejecutó dentro de GitHub Codespaces usando C, y hay razones concretas para cada decisión. Codespaces provee un contenedor Linux aislado con el toolchain de compilación completo (`gcc`, `make`, `linker`), lo que permite compilar un kernel modificado y ejecutar exploits de corrupción de memoria sin poner en riesgo la máquina local. Si algo sale mal durante las pruebas, el daño queda dentro del contenedor y no afecta el host.

C es la única opción práctica para interactuar con el subsistema criptográfico del kernel. `AF_ALG` está escrito en C, y para alinear memoria correctamente, configurar estructuras como `struct msghdr` y `struct cmsghdr`, y forzar la ruta de código que desencadena el fallo in-place, se necesita el control de bajo nivel que solo C ofrece. Cualquier capa de abstracción encima habría ocultado exactamente las condiciones que se querían reproducir y validar.

El entorno además permite empaquetar el sistema de archivos en un `initramfs` y arrancar el kernel modificado con QEMU, lo que hace posible validar en tiempo real si el exploit tiene efecto sobre el kernel parcheado antes de dar el trabajo por terminado.

---

## 2. Modificaciones Realizadas en el Proyecto

El trabajo se dividió en dos frentes: la corrección del código fuente del kernel y la reparación de los scripts de automatización que, sin que fuera evidente a primera vista, impedían que el parche tuviera efecto en el binario compilado.

### A. Modificación en el Kernel (`crypto/algif_aead.c`)

La vulnerabilidad (**CVE-2026-31431**) estaba en `_aead_recvmsg()`. El código pasaba el mismo scatterlist `rsgl_src` como origen y destino en `aead_request_set_crypt`, lo que le decía al kernel que podía escribir los datos cifrados encima de la misma memoria desde donde los estaba leyendo. Bajo ciertas condiciones con pipes y `splice()`, esas páginas no pertenecían al proceso atacante sino al page cache de archivos del sistema, lo que convertía una operación criptográfica en escritura arbitraria sobre ejecutables cacheados en RAM.

```c
// Código vulnerable
aead_request_set_crypt(req, rsgl_src, rsgl_src, asoclen + cryptlen, iv);

// Código corregido
aead_request_set_crypt(req, tsgl_src, rsgl_dst, asoclen + cryptlen, iv);
```

El cambio es de una línea, pero cierra completamente la vulnerabilidad. `tsgl_src` actúa exclusivamente como origen de transmisión (TX SGL) y `rsgl_dst` como destino de recepción (RX SGL). Con buffers estrictamente separados, no existe ruta de código por la que la operación de cifrado pueda aterrizar en páginas que no le corresponden al proceso.

### B. Corrección de Scripts (`scripts/04_build_patched_kernel.sh`)

El script de automatización tenía tres problemas que combinados hacían que el parche nunca llegara al kernel compilado final.

El primero era el menos visible: el script ejecutaba `git stash` justo antes de compilar, revirtiendo silenciosamente el parche del archivo `.c` sin ningún aviso. El compilador procesaba la versión vulnerable del código mientras el desarrollador asumía que estaba trabajando con la versión corregida. Se eliminó esa instrucción.

El segundo era un problema estructural de compilación. `algif_aead` no forma parte del `bzImage` principal sino que se carga como módulo dinámico (`.ko`) en tiempo de ejecución. El script original solo reconstruía el núcleo central, así que el módulo cargado en memoria seguía siendo el vulnerable. Se agregó `make modules` al proceso de compilación y la instalación del módulo en el disco virtual con `make INSTALL_MOD_PATH=... modules_install`.

El tercero era un error de Bash: el script intentaba mover `bzImage_vuln` sobre sí mismo, lo que abortaba el proceso con un `Error 1` antes de terminar. Se corrigió usando una extensión temporal `.bak` como paso intermedio para evitar la colisión de nombres en el sistema de archivos.

---

## 3. Conclusión

Con los buffers separados en `algif_aead.c` y el flujo de compilación de módulos corregido, el kernel parcheado no permite que el exploit escale privilegios. La ruta de código que habilitaba la escritura sobre el page cache de archivos del sistema ya no existe, lo que bloquea el ataque en su origen. El entorno corre bajo el usuario `student` con privilegios restringidos, y el binario explotado ya no puede salir de ese contexto.
