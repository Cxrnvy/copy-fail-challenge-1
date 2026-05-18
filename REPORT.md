
# Reporte Técnico

1. ¿Cuál es el bug raíz y en qué archivo/función está?

El error está en crypto/algif_aead.c, dentro de _aead_recvmsg(). Una optimización de 2017 llamada "in-place encryption" hace que el código pase el mismo scatterlist dos veces a aead_request_set_crypt(...): como origen y como destino. Le dice al kernel que puede escribir los datos cifrados encima de la misma memoria desde donde los está leyendo, sin buffer intermedio, sin separación. Solo, eso no explota. El problema apareció años después, cuando esa decisión encontró pipes y splice().
#
2. ¿Por qué el write a dst[assoclen + cryptlen] es peligroso?

dst no apunta a un buffer privado. Gracias a cómo se encadena la vulnerabilidad con pipes y splice(), ese puntero termina apuntando a páginas físicas del page cache, la memoria que el kernel usa para cachear archivos del disco. No una copia temporal: el caché real que respalda a un ejecutable activo. Cuando el kernel ejecuta la escritura, está inyectando bytes arbitrarios directamente en el código que el sistema va a correr la próxima vez que alguien llame a ese binario.
#
3. ¿Por qué el exploit es "stealthy"?

El disco nunca se toca. El archivo original sigue ahí, intacto, con el mismo hash de siempre. Cualquier auditoría que trabaje desde el sistema de archivos va a devolver un falso negativo. La infección vive solo en RAM, en el page cache, y se borra sola: un reinicio o echo 3 > /proc/sys/vm/drop_caches la elimina sin dejar nada. Sin rootkit, sin persistencia, sin rastro.
#
4. Conecta esto con lo que vimos en clase: page cache, chmod, setuid, inodes

El ataque usa cada concepto para lo que fue diseñado. Se apunta a un inode de un ejecutable con setuid activo, como /usr/bin/su, que corre con privilegios de root sin importar quién lo llame. Al interactuar con él, el kernel lo carga en el page cache. Ahí entra el fallo: la vulnerabilidad criptográfica, combinada con pipes y splice(), permite escribir el payload directamente sobre esas páginas. La próxima llamada al binario ejecuta la versión corrupta desde el caché. El setuid hace el resto: shell como superusuario.
#
5. ¿Qué aprendiste sobre cómo múltiples cambios "razonables" pueden crear un bug grave?

Nadie hizo algo estúpido acá. La optimización de 2017 tenía lógica: reutilizar el buffer ahorra CPU y memoria, y en su contexto era una decisión razonable. El bug no estaba en esa pieza sola sino en cómo interactuó, años después, con pipes y splice(). Dos decisiones correctas por separado que juntas producen escritura arbitraria sobre el page cache. Eso me parece más perturbador que un overflow clásico, porque implica que revisar componentes de forma aislada no es suficiente. La invariante de separar buffers de lectura y escritura no es una regla burocrática: es lo que evita que una optimización razonable de hoy se convierta en vulnerabilidad crítica cuando el sistema crezca.

