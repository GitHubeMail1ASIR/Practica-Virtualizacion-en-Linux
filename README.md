# Práctica Virtualizacion en Linux

Podemos ver una demostración del funcionamiento del [script](script-JJAS.sh) en [este vídeo](Ejecución%20Script.webm).

**IMPORTANTE**: Consideraciones sobre el escenario usado en la ejecución del script:

* El archivo `id_ecdsa` (proporcionado en la entrega por redmine) debe ubicarse en el directorio `~/.ssh/` del usuario que ejecuta el script.

* EL script se puede (y debe) ejecutar completamente sin necesidad de permisos de administrador.

* El árbol de archivos antes de ejecutar el script debería ser similar al siguiente, teniendo en cuenta que el directorio `~/Practica-Virtualizacion-en-Linux/` es obtenido al clonar este repositorio en la home de usuario, y la imagen `bullseye-base-sparse.qcow2` descargada desde el link indicado en redmine se ubica en el mismo directorio:

```bash
~
├── Practica-Virtualizacion-en-Linux
│   ├── README.md
│   ├── bullseye-base-sparse.qcow2
│   └── script-JJAS.sh
└── .ssh
    └── id_ecdsa
```

    * Podríamos tener el script en cualquier directorio realmente, mientras la imagen qcow2 se encuentre en el mismo directorio que el script y el archivo `id_ecdsa` en el directorio `~/.ssh/` del usuario que ejecuta el script.