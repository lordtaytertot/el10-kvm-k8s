# el10-kvm-k8s

## install
```bash
# zeus
ssh-copy-id vm1
```
```
# vm1
sudo visudo
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo sed -i '/swap/d' /etc/fstab

KUBEMINOR=1.33
KUBEPATCH=1.33.0

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBEMINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBEMINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

sudo dnf -y update
sudo dnf -y install kubelet-${KUBEPATCH} kubeadm-${KUBEPATCH} kubectl-${KUBEPATCH} vim yum-utils --disableexcludes=kubernetes
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install containerd

sudo systemctl disable --now firewalld
sudo systemctl enable --now containerd
sudo systemctl enable --now kubelet

containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo br_netfilter | sudo tee /etc/modules-load.d/modules.conf
echo net.bridge.bridge-nf-call-iptables=1 | sudo tee -a /etc/sysctl.conf

rm ~/.bash_history
history -c
sudo poweroff
```
```bash
# zeus
qemu-img create -f qcow2 -o preallocation=metadata /mnt/spare/vm2-vdb.qcow2 100G
qemu-img create -f qcow2 -o preallocation=metadata /mnt/spare/vm3-vdb.qcow2 100G

sudo virt-clone \
  --original vm1 \
  --name vm2 \
  --mac 52:54:00:00:00:02 \
  --file /mnt/spare/vm2-vda.qcow2

sudo virt-clone \
  --original vm1 \
  --name vm3 \
  --mac 52:54:00:00:00:03 \
  --file /mnt/spare/vm3-vda.qcow2

sudo virsh attach-disk vm2 /mnt/spare/vm2-vdb.qcow2 vdb --persistent
sudo virsh attach-disk vm3 /mnt/spare/vm3-vdb.qcow2 vdb --persistent

sudo virsh snapshot-create-as vm1 base --disk-only
sudo virsh snapshot-create-as vm2 base --disk-only
sudo virsh snapshot-create-as vm3 base --disk-only

./power.sh start

ssh vm1 "sudo kubeadm init --apiserver-advertise-address 192.168.1.41 --pod-network-cidr '10.244.0.0/16'"
ssh vm1 "mkdir -p ~/.kube/ && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown james:james ~/.kube/config"
scp vm1:~/.kube/config ~/.kube/config

ssh vm2 "sudo kubeadm join 192.168.1.41:6443 --token ... \
        --discovery-token-ca-cert-hash sha256:..."
ssh vm3 "sudo kubeadm join 192.168.1.41:6443 --token ... \
        --discovery-token-ca-cert-hash sha256:..."

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

ssh vm2 'sudo pvcreate /dev/vdb ; sudo vgcreate local /dev/vdb ;
        for i in {0..9}; do
          if [[ ${i} == 9 ]]; then
            sudo lvcreate -n lv${i} -l 100%FREE local
            continue
          fi
          sudo lvcreate -n lv${i} -L 10G local
        done ;
        for i in {0..9}; do
          sudo mkfs.xfs /dev/mapper/local-lv${i}
          sudo mkdir /mnt/local-lv${i}
          sudo mount /dev/mapper/local-lv${i} /mnt/local-lv${i}
        done'
ssh vm3 'sudo pvcreate /dev/vdb ; sudo vgcreate local /dev/vdb ;
        for i in {0..9}; do
          if [[ ${i} == 9 ]]; then
            sudo lvcreate -n lv${i} -l 100%FREE local
            continue
          fi
          sudo lvcreate -n lv${i} -L 10G local
        done ;
        for i in {0..9}; do
          sudo mkfs.xfs /dev/mapper/local-lv${i}
          sudo mkdir /mnt/local-lv${i}
          sudo mount /dev/mapper/local-lv${i} /mnt/local-lv${i}
        done'

./setup-storage.sh

ssh vm1 "rm ~/.bash_history ; history -c ; sudo poweroff"
ssh vm2 "rm ~/.bash_history ; history -c ; sudo poweroff"
ssh vm3 "rm ~/.bash_history ; history -c ; sudo poweroff"

sudo virsh snapshot-create-as vm1 v${KUBEPATCH} --disk-only
sudo virsh snapshot-create-as vm2 v${KUBEPATCH} --disk-only
sudo virsh snapshot-create-as vm3 v${KUBEPATCH} --disk-only
```

## utils
```bash
./power.sh 
usage: ./power.sh ( start || shutdown )
```

## upgrade
```bash
cd ~/dev/ansible/
ansible vm -b -m shell -a "dnf clean all"
ansible vm -b -m dnf -a "name='*' state=latest"

KUBEPATCH=1.33.1
ansible vm -b -a "dnf update -y --disableexcludes=kubernetes kubeadm-${KUBEPATCH} kubelet-${KUBEPATCH} kubectl-${KUBEPATCH}"
ssh vm1 "sudo kubeadm upgrade plan v${KUBEPATCH}"
ssh vm1 "sudo kubeadm upgrade apply v${KUBEPATCH}"
ansible vm2,vm3 -b -a 'kubeadm upgrade node'
ansible vm -b -a 'systemctl daemon-reload'
ansible vm -b -a 'systemctl restart kubelet'
```