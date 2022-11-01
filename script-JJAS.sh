#!/usr/bin/env bash

# Variables para poner texto en negrita y de vuelta a normal:
bold=$(tput bold)
normal=$(tput sgr0)

# Aviso inicial para prevenir errores:
echo "${bold}Este script debe ejecutarse con el comando . o con source, de lo contrario fallará.${normal}"
sleep 2
echo "${bold}Ejemplo de sintáxis correcta: . ./script-JJAS.sh${normal}"
sleep 2
echo -e "${bold}Si ha ejecutado el script de una forma errónea, pulse Ctrl+C para cancelar la ejecución ahora.${normal}\n"
sleep 2
read -p "${bold}Presione enter si ha leído y entendido lo arriba explicado y desea continuar la ejecución.${normal}"

# Ahora me aseguraré de que existe el fichero ~/.ssh/id_ecdsa en el host, de lo contrario se cancelará la ejecución ya que no podremos conectarnos por ssh:
if [ -f ~/.ssh/id_ecdsa ]; then
    echo -e "\n${bold}Existencia del fichero ~/.ssh/id_ecdsa comprobada, continuando con la ejecución del script...${normal}"
    sleep 2
else
    echo -e "\n${bold}No existe el fichero ~/.ssh/id_ecdsa. Cancelando la ejecución.${normal}";
    return 1
fi

# Finalmente me aseguraré de que existe el fichero /var/lib/libvirt/images/bullseye-base.qcow2:
if [ -f /var/lib/libvirt/images/bullseye-base.qcow2 ]; then
    echo -e "\n${bold}Existencia del fichero /var/lib/libvirt/images/bullseye-base.qcow2 comprobada, continuando con la ejecución del script...${normal}"
    echo
    sleep 2
else
    echo -e "\n${bold}No existe el fichero /var/lib/libvirt/images/bullseye-base.qcow2. Cancelando la ejecución.${normal}";
    return 1
fi

# Crear una imagen nueva, que utilice bullseye-base.qcow2 como imagen base y tenga 5 GiB de tamaño máximo. Esta imagen se denominará maquina1.qcow2:
echo -e "${bold}Intentando obtener permisos de administrador para los comandos que lo necesitan...${normal}\n"

sleep 2

sudo qemu-img create -f qcow2 -b /var/lib/libvirt/images/bullseye-base.qcow2 /var/lib/libvirt/images/maquina1.qcow2 5G

sudo cp /var/lib/libvirt/images/maquina1.qcow2 /var/lib/libvirt/images/newmaquina1.qcow2

sudo virt-resize --expand /dev/sda1 /var/lib/libvirt/images/maquina1.qcow2 /var/lib/libvirt/images/newmaquina1.qcow2

sudo mv /var/lib/libvirt/images/newmaquina1.qcow2 /var/lib/libvirt/images/maquina1.qcow2


# Crea una red interna de nombre intra con salida al exterior mediante NAT que utilice el direccionamiento 10.10.20.0/24:
echo "<network>
    <name>intra</name>
    <bridge name='virbr24'/>
    <forward/>
    <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
        <range start='10.10.20.2' end='10.10.20.254'/>
    </dhcp>
    </ip>
</network>" > intra.xml

echo

virsh -c qemu:///system net-define intra.xml

virsh -c qemu:///system net-start intra

virsh -c qemu:///system net-autostart intra


# Crea una máquina virtual (maquina1) conectada a la red intra, con 1 GiB de RAM, que utilice como disco raíz maquina1.qcow2 y que se inicie automáticamente. Arranca la máquina. Modifica el fichero /etc/hostname con maquina1:
virt-install --connect qemu:///system --name maquina1 --ram 1024 --vcpus 1 --disk /var/lib/libvirt/images/maquina1.qcow2 --network network=intra --os-type linux --os-variant debian10 --import --noautoconsole


# Autoiniciar la máquina:
virsh -c qemu:///system autostart maquina1


# Nota:
# Los sleep que nos encontramos a partir de ahora son necesarios para evitar errores de ejecución.


# Obtener su IP y guardarla en una variable:
echo -e "${bold}Esperando un tiempo prudencial de 20s hasta que la vm esté arrancada...${normal}\n"

sleep 20

IP=$(virsh -c qemu:///system domifaddr maquina1 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)


# Cambiar el hostname:
ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'echo "maquina1" > /etc/hostname'"


# Crea un volumen adicional de 1 GiB de tamaño en formato RAW ubicado en el pool por defecto:
virsh -c qemu:///system vol-create-as default maquina1-1G.raw 1G --format raw


# Una vez iniciada la MV maquina1, conecta el volumen a la máquina, crea un sistema de ficheros XFS en el volumen y móntalo en el directorio /var/www/html. Ten cuidado con los propietarios y grupos que pongas, para que funcione adecuadamente el siguiente punto:
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/maquina1-1G.raw vdb --targetbus virtio --persistent

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c '/usr/sbin/mkfs.xfs -f /dev/vdb && mkdir -p /var/www/html && mount /dev/vdb /var/www/html && chown -R www-data:www-data /var/www/html && chmod -R 755 /var/www/html'"

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'echo "/dev/vdb /var/www/html xfs defaults 0 0" >> /etc/fstab'"


# Instala en maquina1 el servidor web apache2:
ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'apt update && apt install -y apache2 && sudo systemctl enable --now apache2'"


# Copia un fichero index.html a la máquina virtual:
echo "Este es el fichero index.html de la VM maquina1. Significa que el servidor apache2 funciona correctamente." > index.html

echo

scp -i ~/.ssh/id_ecdsa index.html debian@$IP:/home/debian/index.html

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'mv /home/debian/index.html /var/www/html/index.html'"


# Muestra por pantalla la IP de la VM maquina1. Pausa el script y comprueba que puedes acceder a la página web:
echo -e "\n${bold}La IP de la VM maquina1 es: $IP${normal}"

sleep 2

read -p "${bold}Script pausado para comprobar que se puede acceder a la página web. Pulsa enter para continuar...${normal}"

echo


# Instala LXC en la vm maquina1 y crea un linux container llamado container1:
ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'apt update && apt install -y lxc && lxc-create -t download -n container1 -- -d debian -r bullseye -a amd64'"


# Añade una nueva interfaz a la máquina virtual para conectarla a la red pública (al puente br0).
virsh -c qemu:///system shutdown maquina1

sleep 12

virsh -c qemu:///system attach-interface maquina1 bridge br0 --model virtio --config

virsh -c qemu:///system start maquina1

echo -e "${bold}Esperando un tiempo prudencial de 20s hasta que la vm esté arrancada...${normal}\n"

sleep 20


# Configuramos la nueva interfaz de red en la máquina virtual y muestra la IP de la nueva interfaz:
ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'echo "allow-hotplug enp8s0" >> /etc/network/interfaces && echo "iface enp8s0 inet dhcp" >> /etc/network/interfaces'"

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo -- bash -c 'dhclient -r && dhclient'"

sleep 8

echo -e "\n${bold}La IP de la nueva interfaz por br0 es: ${normal}"

ssh -i ~/.ssh/id_ecdsa debian@$IP "ip a show enp8s0 | grep inet | cut -d/ -f1 | head -n 1 | grep -oP '(\d+\.){3}\d+'" | sed 's/ //g'

echo

read -p "${bold}Pulse alguna tecla para continuar...${normal}"

echo


# Apaga maquina1 y auméntale la RAM a 2 GiB y vuelve a iniciar la máquina.
virsh -c qemu:///system shutdown maquina1

sleep 12

virsh -c qemu:///system setmaxmem maquina1 2G --config

virsh -c qemu:///system setmem maquina1 2G --config

echo -e "${bold}Memoria RAM de la VM aumentada a 2GiB, iniciando...${normal}\n"

virsh -c qemu:///system start maquina1

echo "${bold}Esperando un tiempo prudencial de 20s hasta que la vm esté completamente arrancada...${normal}"

sleep 20


# Crea un snapshot de la máquina virtual.
echo -e "\nCreando snapshot de la máquina virtual...\n"

virsh -c qemu:///system snapshot-create-as maquina1 --name "snapshot1" --description "Snapshot de la máquina virtual" --disk-only --atomic

# Fin
echo -e "\n${bold}Script finalizado.${normal}"