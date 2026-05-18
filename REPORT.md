Reporte Técnico

1. ¿Cuál es el bug raíz y en qué archivo/función está?
El error reside en el archivo `crypto/algif_aead.c`, específicamente en la función `_aead_recvmsg()`. La vulnerabilidad surge por una optimización de rendimiento introducida en 2017 ("in-place encryption") que utilizaba el mismo buffer de memoria tanto para la entrada como para la salida de datos. Al invocar `aead_request_set_crypt(...)` pasándole el mismo scatterlist (`rsgl_src, rsgl_src`), el kernel permite que los datos se escriban directamente sobre la memoria que debería ser de solo lectura.

2. ¿Por qué el write a `dst[assoclen + cryptlen]` es peligroso?
Es extremadamente peligroso porque, debido a la vulnerabilidad, ese destino (`dst`) apunta a páginas físicas de memoria que pertenecen al *page cache* de un archivo del sistema. El kernel, en lugar de escribir en un espacio privado, termina inyectando datos arbitrarios (nuestro payload malicioso) directamente en la memoria caché que respalda a un archivo ejecutable crítico.

3. ¿Por qué el exploit es "stealthy" (no modifica el archivo en disco)?
El ataque es sigiloso porque ocurre exclusivamente en la memoria RAM (en el Page Cache). El archivo original guardado en el disco duro nunca es alterado. Si un administrador audita el disco o verifica los hashes de los binarios, todo parecerá normal. Además, cualquier reinicio del sistema o limpieza de memoria (`echo 3 > /proc/sys/vm/drop_caches`) borra la infección sin dejar rastro persistente.

4. Conecta esto con lo que vimos en clase: page cache, chmod, setuid, inodes
El exploit orquesta todos estos elementos: Primero, apuntamos a un `inode` específico que corresponde a un ejecutable con el bit `setuid` activado mediante `chmod` (como `/usr/bin/su`, que se ejecuta con privilegios de root). Al intentar interactuar con él, el kernel carga el archivo en el `page cache`. Luego, explotando el fallo criptográfico, corrompemos esa página en memoria. Finalmente, al ejecutar el binario, el sistema lanza nuestra versión corrompida desde el caché, y gracias al `setuid`, nos entrega una consola como superusuario.

5. ¿Qué aprendiste sobre cómo múltiples cambios "razonables" pueden crear un bug grave?
Este caso ilustra que aislar los componentes no es suficiente en sistemas complejos. La optimización "in-place" de 2017 era completamente razonable para ahorrar ciclos de CPU y RAM, y por sí sola no era peligrosa. Sin embargo, años después, al interactuar con el uso legítimo de tuberías (pipes) y la llamada al sistema `splice()`, esa pequeña optimización se convirtió en una vulnerabilidad crítica. Nos enseña que separar físicamente los buffers de lectura (input) y escritura (output) es una regla de seguridad que no debe romperse por motivos de rendimiento.