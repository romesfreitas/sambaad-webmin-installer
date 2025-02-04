#!/bin/bash

# Verifica se o dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "📦 Instalando o pacote 'dialog'..."
    apt update && apt install -y dialog
fi

# Arquivo temporário para armazenar as entradas do usuário
tempfile=$(mktemp)

# Exibe a interface para coletar as informações do usuário
dialog --title "Configuração do Controlador de Domínio" --form "Insira os dados abaixo:" 15 60 6 \
    "Nome do Domínio (FQDN):" 1 1 "" 1 25 30 0 \
    "Nome NETBIOS:" 2 1 "" 2 25 30 0 \
    "Senha do Administrador:" 3 1 "" 3 25 30 0 \
    "IP Fixo do Servidor:" 4 1 "" 4 25 30 0 \
    "Máscara de Rede:" 5 1 "" 5 25 30 0 \
    "Gateway:" 6 1 "" 6 25 30 0 \
    2> $tempfile

# Lê os dados inseridos
read -r DOMAIN NETBIOS PASSWORD IP MASCARA GATEWAY < $tempfile
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# Remove o arquivo temporário
rm -f $tempfile

# Confirmação das informações inseridas
dialog --title "Confirmação" --yesno "Confirme os dados:\n\nDomínio: $DOMAIN\nNETBIOS: $NETBIOS\nIP: $IP\nMáscara: $MASCARA\nGateway: $GATEWAY" 12 50
if [[ $? -ne 0 ]]; then
    echo "❌ Instalação cancelada pelo usuário."
    exit 1
fi

echo "🚀 Atualizando sistema..."
apt update && apt upgrade -y

echo "🔧 Instalando pacotes necessários..."
apt install -y samba smbclient krb5-user winbind libnss-winbind libpam-winbind libpam-krb5 webmin

echo "🌍 Configurando rede..."
cat <<EOF > /etc/network/interfaces
auto eth0
iface eth0 inet static
    address $IP
    netmask $MASCARA
    gateway $GATEWAY
    dns-nameservers 8.8.8.8 8.8.4.4
EOF

systemctl restart networking

echo "🌍 Configurando Samba AD..."
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = $NETBIOS
   realm = $REALM
   netbios name = $NETBIOS
   server role = active directory domain controller
   dns forwarder = 8.8.8.8

[sysvol]
   path = /var/lib/samba/sysvol
   read only = No

[netlogon]
   path = /var/lib/samba/sysvol/$DOMAIN/scripts
   read only = No
EOF

echo "⚙️ Provisionando o domínio..."
echo -e "$PASSWORD\n$PASSWORD" | samba-tool domain provision --use-rfc2307 --realm=$REALM --domain=$NETBIOS --adminpass="$PASSWORD"

echo "🔄 Reiniciando serviços..."
systemctl restart samba-ad-dc

echo "✅ Configuração concluída! Acesse o Webmin via https://$IP:10000"
