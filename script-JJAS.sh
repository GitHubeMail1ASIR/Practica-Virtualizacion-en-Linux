#!/bin/bash

# Antes de comenzar comprobaré que el script ha sido ejecutado con permisos de administrador, de lo contrario se cancelará la ejecución:
if [ $(id -u) = 0 ]; then
	return 0;
else
	echo "Este script debe ser ejecutado con permisos de administrador. Cancelando la ejecución.";
	exit
fi

# Ahora me aseguraré de que existe el fichero ~/.ssh/id_ecdsa en el host, de lo contrario se cancelará la ejecución ya que no podremos conectarnos por ssh:
if [ -f ~/.ssh/id_ecdsa ]; then
    return 0;
else
    echo "No existe el fichero ~/.ssh/id_ecdsa. Cancelando la ejecución.";
    exit
fi

# Crear una imagen nueva, que utilice bullseye-base.qcow2 como imagen base y tenga 5 GiB de tamaño máximo. Esta imagen se denominará maquina1.qcow2:
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

virsh -c qemu:///system net-define intra.xml

virsh -c qemu:///system net-start intra

virsh -c qemu:///system net-autostart intra


# Crea una máquina virtual (maquina1) conectada a la red intra, con 1 GiB de RAM, que utilice como disco raíz maquina1.qcow2 y que se inicie automáticamente. Arranca la máquina. Modifica el fichero /etc/hostname con maquina1:
virt-install --connect qemu:///system --name maquina1 --ram 1024 --vcpus 1 --disk /var/lib/libvirt/images/maquina1.qcow2 --network network=intra --os-type linux --os-variant debian10 --import


# Autoiniciar la máquina:
virsh -c qemu:///system autostart maquina1


# Arrancar la máquina:
virsh -c qemu:///system start maquina1


# Obtener su IP y guardarla en una variable:
IP=$(virsh -c qemu:///system domifaddr maquina1 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)


# Cambiar el hostname:
ssh -i ~/.ssh/id_ecdsa debian@$IP "su root -c 'echo "maquina1" > /etc/hostname'"


# Crea un volumen adicional de 1 GiB de tamaño en formato RAW ubicado en el pool por defecto:
virsh -c qemu:///system vol-create-as default maquina1-1G.raw 1G --format raw


# Una vez iniciada la MV maquina1, conecta el volumen a la máquina, crea un sistema de ficheros XFS en el volumen y móntalo en el directorio /var/www/html. Ten cuidado con los propietarios y grupos que pongas, para que funcione adecuadamente el siguiente punto:
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/maquina1-1G.raw vdb --targetbus virtio --persistent

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo su root -c '/usr/sbin/mkfs.xfs -f /dev/vdb' && mkdir -p /var/www/html && mount /dev/vdb /var/www/html && chown -R www-data:www-data /var/www/html && chmod -R 755 /var/www/html"

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo su root -c 'echo "/dev/vdb /var/www/html xfs defaults 0 0" >> /etc/fstab'"


# Instala en maquina1 el servidor web apache2. Copia un fichero index.html a la máquina virtual:
echo "Holi mundo" > index.html

scp -i ~/.ssh/id_ecdsa index.html debian@$IP:/var/www/html

ssh -i ~/.ssh/id_ecdsa debian@$IP "sudo su root -c 'apt update && apt install -y apache2 && sudo systemctl enable --now apache2'"


# Muestra por pantalla la IP de la VM maquina1. Pausa el script y comprueba que puedes acceder a la página web:
echo "La IP de la VM maquina1 es: $IP"

read -p "Script pausado para comprobar que se puede acceder a la página web. Pulsa enter para continuar..."


# Instala LXC y crea un linux container llamado container1:
sudo apt install -y lxc

sudo lxc-create -t download -n container1 -- -d debian -r bullseye -a amd64

# Los sleep que nos encontramos a partir de ahora son necesarios para evitar errores de ejecución.

# Añade una nueva interfaz a la máquina virtual para conectarla a la red pública (al puente br0).
virsh -c qemu:///system shutdown maquina1

sleep 12

virsh -c qemu:///system attach-interface maquina1 bridge br0 --model virtio --config

virsh -c qemu:///system start maquina1

sleep 12


# Muestra la nueva IP que ha recibido.
ssh -i ~/.ssh/id_ecdsa debian@$IP "echo 'La nueva IP es:' && ip a show enp8s0 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1"

read -p "Pulse alguna tecla para continuar..."


# Apaga maquina1 y auméntale la RAM a 2 GiB y vuelve a iniciar la máquina.
virsh -c qemu:///system shutdown maquina1

sleep 12

virsh -c qemu:///system setmaxmem maquina1 2G --config

virsh -c qemu:///system setmem maquina1 2G --config

virsh -c qemu:///system start maquina1


# Crea un snapshot de la máquina virtual.
virsh -c qemu:///system snapshot-create-as maquina1 --name "snapshot1" --description "Snapshot de la máquina virtual" --disk-only --atomic