
# Reporte Técnico - Copy Fail — CVE-2026-31431

## 1. ¿Cuál es el bug raíz y en qué archivo/función está?

El error está en crypto/algif_aead.c, dentro de _aead_recvmsg(). En 2017 se introdujo una optimización llamada "in-place encryption": en lugar de reservar un buffer separado para la salida del cifrado, el código pasa el mismo scatterlist rsgl_src tanto como fuente como destino en aead_request_set_crypt(...). Le dice al kernel que puede escribir los datos cifrados encima de la misma memoria desde donde los lee. Bajo condiciones normales la operación termina antes de necesitar los datos originales, así que nada explota. La suposición implícita es que nadie más tiene una referencia a esas páginas. Con pipes y splice(), esa suposición deja de ser válida.
#
## 2. ¿Por qué el write a dst[assoclen + cryptlen] es peligroso?

dst no apunta a un buffer privado. Cuando se combina la vulnerabilidad con splice(), el kernel mapea páginas del page cache de un archivo directamente en el scatterlist de la operación criptográfica, sin hacer una copia privada. splice() existe precisamente para evitar copias intermedias en transferencias de datos, lo cual lo hace eficiente para I/O, pero aquí ese mismo mecanismo expone páginas del caché como destino de escritura. Cuando el cifrado in-place ejecuta, el kernel escribe bytes controlados por el atacante sobre esas páginas: sobre el contenido de archivos del sistema que están cacheados en RAM. No hay sandbox, no hay copia de seguridad, no hay vuelta atrás hasta el próximo reinicio.
#
## 3. ¿Por qué el exploit es "stealthy"?

El disco nunca se toca. El archivo original queda intacto, con el mismo hash y los mismos permisos. Herramientas como sha256sum, debsums, o rpm -V van a reportar que todo está bien, porque en disco todo efectivamente está bien. La infección existe solo en el page cache, en RAM. Y se autodestruye: un reinicio o echo 3 > /proc/sys/vm/drop_caches vacía el caché y borra cualquier rastro sin dejar nada persistente. No necesita rootkit, no necesita tocar el initramfs, no necesita sobrevivir al apagado. Desde el punto de vista forense, es como si nunca hubiera ocurrido.
#
## 4. Conecta esto con lo que vimos en clase: page cache, chmod, setuid, inodes

El ataque no hace nada que el sistema operativo no esté diseñado para hacer. El objetivo es un ejecutable con el bit setuid activo, como /usr/bin/su o /usr/bin/sudo, binarios que el kernel ejecuta con los privilegios de su propietario (root) sin importar quién los llame. Ese bit se configura con chmod u+s y queda registrado en los metadatos del inode. Cuando cualquier proceso interactúa con ese binario, el kernel lo carga en el page cache identificado por su inode, porque leer desde disco en cada ejecución sería prohibitivamente lento. A partir de ahí, todas las ejecuciones usan el caché. El exploit entra justo ahí: usando la vulnerabilidad criptográfica con splice(), escribe el payload sobre esas páginas cacheadas. La siguiente llamada al binario ejecuta el código del atacante. Y gracias al setuid, ese código corre como root.
#
## 5. ¿Qué aprendiste sobre cómo múltiples cambios "razonables" pueden crear un bug grave?


Nadie hizo algo descuidado acá, y eso es lo que me resulta más difícil de procesar. La optimización de 2017 tenía justificación técnica real: in-place encryption reduce la presión sobre el allocator, baja el uso de memoria y mejora la localidad de caché. splice() también tiene su razón de existir: transferir datos sin copias intermedias es lo que necesitás para I/O de alta velocidad. Ninguno de los dos era un error. El problema es que al combinarse produjeron algo que ninguno tenía por separado: la capacidad de escribir datos controlados por el usuario directamente sobre páginas del page cache de archivos del sistema. Prevenir eso requería razonar sobre las interacciones entre dos subsistemas que ni siquiera se comunican directamente entre sí, lo cual es mucho más difícil que encontrar un buffer overflow. La conclusión práctica es que separar los buffers de entrada y salida en operaciones criptográficas del kernel no es una convención de estilo: es una invariante de seguridad que no se negocia cuando el rendimiento aprieta.

