# What is this?

This project will help you deploy a basic Kubernetes cluster per [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
on AWS using Spot Instances. Using `t2.medium` instances, this toy cluster will cost you less than $1/day.

A future commit will enable examples for other cloud providers aside from GCP.

# When Should I Use This?

✓ You're trying to pass the [Certified Kubernetes Administrator](https://www.cncf.io/certification/cka/) exam.

✓ You're interested in seeing how absolutely involved a Kubernetes setup is so you can appreciate [kops](https://github.com/kubernetes/kops) or [kubespray](https://github.com/kubernetes-incubator/kubespray) more,

✓ You're trying to deploy Kubernetes onto a platform that's not supported by other installers and are looking for a starting point.

✓ You hate yourself.

✓ You've won the cryptocurrency lottery, are now retired and find yourself with many, many, *many* hours to burn.

# When Shouldn't I Use This?

**Any other time.**

# Really?

Yes. Use kops, kubespray, or a managed Kubernetes offering.

# Why?

- This codebase does not provision triggers to account for random nodes dying due to getting outbid on the Spot market.
  Deploying this will likely cause split-brains, randomly-dying `Pod`s, CNI black holes and other misadventures.
- kube-dns also seems to be broken. Records will resolve for `Pod`s that live on the same node as the kube-dns `Pod`. 
  This happens because the bridge network created by CNI is unable to find a route from workers that are not
  hosting kube-dns to workers that are, and kube-dns is not a `DaemonSet`.
- None of this is tested at all, unfortunately, outside of a few verifications made by Ansible playbooks.

# Still interested in using this?

Cool! Here are some instructions to help you out.

## Deploying

1. Copy the `.env.example`: `cat .env.example | grep -Ev '^#' > .env`
2. Fill in the environment variables provided with your desired values.
3. Run `make deploy_cluster`. You will hear one bell when SSH access is available and three bells when Kubernetes is accessible.
   **NOTE**: This takes between 5-10 minutes to provision.
4. Confirm that your cluster is available: `kubectl get cs`

## Destroying

Run `make destroy_cluster` to wipe your cluster. You'll hear one bell when this is done.

**NOTE**: This takes 2-5 minutes to complete.

## Troubleshooting

There are several Make targets that can help you in your (unfortunately) inevitable troubleshooting efforts.

- `get_control_plane_addresses`: Retrieves IP addresses for all Kubernetes controllers
- `get_worker_addresses`: Same as above, but for workers.
- `get_etcd_node_addresses`: Same as above, but for your `etcd` cluster.
- `ssh_into_kubernetes_controller`: `echo`s a SSH command to run to SSH into any Kubernetes controller
- `ssh_into_kubernetes_worker`: Same, but for workers.
- `ssh_into_etcd_node`: Same, but for `etcd` nodes.
- `recycle_nodes`: Deletes and recreates Kubernetes nodes while keeping all other infrastructure intact.
- `recycle_cluster`: Same as `destroy_cluster` and `deploy_cluster`.
- `recycle_controllers`: Same as `recycle_nodes`, but for controllers.
- `recycle_workers`: Same as `recycle_nodes`, but for workers.
- `recycle_etcd_nodes`: Same as `recycle_nodes`, but for etcd nodes.
- `run_configuration_manually`: Drops into the container for your desired configuration management tool to run code manually.

# Maintenance and Support

I'll gladly accept PRs to fix things that I've missed. However, please do not expect any sort of timely support.
