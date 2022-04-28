// Deploys a dashboard showing cluster-wide information
local grafana = import '../vendor/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;

local jupyterhub = import './jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current=null,
    hide='label',
  ),
];

// Cluster-wide stats
local userNodes = graphPanel.new(
  'Node Count',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
    expr='sum(kube_node_labels) by (label_cloud_google_com_gke_nodepool)',
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
);

local userPods = graphPanel.new(
  'Running Users',
  description=|||
    Count of running users, grouped by namespace
  |||,
  decimals=0,
  min=0,
  stack=true,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase="Running"}
        %s
      ) by (namespace)
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_right='', namespace=null),
    legendFormat='{{namespace}}'
  ),
]);

local clusterMemoryCommitment = graphPanel.new(
  'Memory commitment %',
  formatY1='percentunit',
  description=|||
    % of total memory in the cluster currently requested by to non-placeholder pods.

    If autoscaling is efficient, this should be a fairly constant, high number (>70%).
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        (
          # Get individual container memory requests
          kube_pod_container_resource_requests_memory_bytes
          # Add node pool name as label
          * on(node) group_left(label_cloud_google_com_gke_nodepool) kube_node_labels{}
        )
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (label_cloud_google_com_gke_nodepool)
      /
      sum(
        # Total allocatable memory on a node
        kube_node_status_allocatable_memory_bytes
        # Add nodepool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool) kube_node_labels{}
      ) by (label_cloud_google_com_gke_nodepool)
    |||,
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
]);

local clusterCPUCommitment = graphPanel.new(
  'CPU commitment %',
  formatY1='percentunit',
  description=|||
    % of total CPU in the cluster currently requested by to non-placeholder pods.

    JupyterHub users mostly are capped by memory, so this is not super useful.
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        (
          # Get individual container memory requests
          kube_pod_container_resource_requests_cpu_cores
          # Add node pool name as label
          * on(node) group_left(label_cloud_google_com_gke_nodepool) kube_node_labels{}
        )
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (label_cloud_google_com_gke_nodepool)
      /
      sum(
        # Total allocatable memory on a node
        kube_node_status_allocatable_cpu_cores
        # Add nodepool name as label
        * on(node) group_left(label_cloud_google_com_gke_nodepool) kube_node_labels{}
      ) by (label_cloud_google_com_gke_nodepool)
    |||,
    legendFormat='{{label_cloud_google_com_gke_nodepool}}'
  ),
]);


local nodeCPUCommit = graphPanel.new(
  'Node CPU Commit %',
  formatY1='percentunit',
  description=|||
    % of each node guaranteed to pods on it
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container memory limits
        kube_pod_container_resource_requests_cpu_cores
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node)
      /
      sum(
        # Get individual container memory requests
        kube_node_status_allocatable_cpu_cores
      ) by (node)
    |||,
    legendFormat='{{node}}'
  ),
]);

local nodeMemoryCommit = graphPanel.new(
  'Node Memory Commit %',
  formatY1='percentunit',
  description=|||
    % of each node guaranteed to pods on it
  |||,
  min=0,
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # Get individual container memory limits
        kube_pod_container_resource_requests_memory_bytes
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node)
      /
      sum(
        # Get individual container memory requests
        kube_node_status_allocatable_memory_bytes
      ) by (node)
    |||,
    legendFormat='{{node}}'
  ),
]);

// Cluster diagnostics
local nodeMemoryUtil = graphPanel.new(
  'Node Memory Utilization %',
  formatY1='percentunit',
  description=|||
    % of available Memory currently in use
  |||,
  min=0,
  // since this is actual measured utilization, it should not be able to exceed max=1
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      1 - (
        sum (
          # Memory that can be allocated to processes when they need
          node_memory_MemFree_bytes + # Unused bytes
          node_memory_Cached_bytes + # Shared memory + temporary disk cache
          node_memory_Buffers_bytes # Very temporary buffer memory cache for disk i/o
        ) by (kubernetes_node)
        /
        sum(node_memory_MemTotal_bytes) by (kubernetes_node)
      )
    |||,
    legendFormat='{{kubernetes_node}}'
  ),
]);

local nodeCPUUtil = graphPanel.new(
  'Node CPU Utilization %',
  formatY1='percentunit',
  description=|||
    % of available CPUs currently in use
  |||,
  min=0,
  // since this is actual measured utilization, it should not be able to exceed max=1
  max=1,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (kubernetes_node)
      /
      sum(
        # Rename 'node' label to 'kubernetes_node', since kube-state-metrics to match metric from
        # kube-state-metrics to prometheus node exporter
        label_replace(kube_node_status_capacity_cpu_cores, "kubernetes_node", "$1", "node", "(.*)")
      ) by (kubernetes_node)
    |||,
    legendFormat='{{kubernetes_node}}'
  ),
]);


local nonRunningPods = graphPanel.new(
  'Non Running Pods',
  description=|||
    Pods in states other than 'Running'.

    In a functional clusters, pods should not be in non-Running states for long.
  |||,
  decimals=0,
  legend_hideZero=true,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(kube_pod_status_phase{phase!="Running"}) by (phase)',
    legendFormat='{{phase}}',
  ),
]);


dashboard.new(
  'Cluster Information',
  tags=['jupyterhub', 'kubernetes'],
  editable=true
).addTemplates(
  templates
).addPanel(
  row.new('Cluster Stats'), {},
).addPanel(
  userPods, { w: standardDims.w * 2 },
).addPanel(
  clusterMemoryCommitment, {},
).addPanel(
  clusterCPUCommitment, {},
).addPanel(
  userNodes, {},
).addPanel(
  nonRunningPods, {},

).addPanel(
  row.new('Node Stats'), {},
).addPanel(
  nodeCPUUtil, {},
).addPanel(
  nodeMemoryUtil, {},
).addPanel(
  nodeCPUCommit, {},
).addPanel(
  nodeMemoryCommit, {},
)