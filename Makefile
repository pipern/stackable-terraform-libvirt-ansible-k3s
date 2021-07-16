all: venv terraform ansible sign

TERRAFORM=/usr/bin/terraform
# docker.io/hashicorp/terraform is missing mkisofs - maybe we should make a 'tools' image that has terraform, ansible, etc...
# TERRAFORM=podman run --group-add keep-groups -v `pwd`:/work -v /var/run/libvirt:/var/run/libvirt docker.io/hashicorp/terraform:1.0.2 -chdir=/work

venv:
	# TODO podman?
	virtualenv --python python3 .ansible-venv
	./.ansible-venv/bin/python -m pip install -r python/requirements.txt
	./.ansible-venv/bin/ansible-galaxy collection install -p .ansible-venv -r ansible/requirements.yml

terraform:
	$(TERRAFORM) init
	$(TERRAFORM) apply -auto-approve

ansible:
	./.ansible-venv/bin/ansible-playbook -i generated-inventory.yml stackable.yml

sign:
	KUBECONFIG=`pwd`/kubeconfig kubectl get csr
	KUBECONFIG=`pwd`/kubeconfig kubectl certificate approve worker-2-tls
	KUBECONFIG=`pwd`/kubeconfig kubectl certificate approve worker-3-tls
	KUBECONFIG=`pwd`/kubeconfig kubectl get nodes
	echo "You can use 'terraform show' to see the IP addresses"

down:
	# TODO is the auto-approve a good idea?
	$(TERRAFORM) destroy -auto-approve

.PHONY: venv terraform ansible sign all down
