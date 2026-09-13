/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	mysqlv1 "example.com/mysql-operator/api/v1"
)

const mysqlFinalizer = "mysql.example.com/finalizer"

// MySQLReconciler reconciles a MySQL object
type MySQLReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=mysql.example.com,resources=mysqls,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=mysql.example.com,resources=mysqls/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=mysql.example.com,resources=mysqls/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=batch,resources=cronjobs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=persistentvolumeclaims,verbs=get;list;watch;delete

// Reconcile 把 MySQL CR 收敛为：Headless Service + ClusterIP Service +
// StatefulSet（数据 PVC 由 volumeClaimTemplates 供给）+ 可选备份 CronJob。
// 删除时通过 Finalizer 清理遗留的 PVC（防止数据孤儿）。
func (r *MySQLReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := logf.FromContext(ctx).WithValues("mysql", req.NamespacedName)

	var db mysqlv1.MySQL
	if err := r.Get(ctx, req.NamespacedName, &db); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// ---- 删除分支：清理 PVC（数据 + 备份），再放行删除 ----
	if !db.DeletionTimestamp.IsZero() {
		if controllerutil.ContainsFinalizer(&db, mysqlFinalizer) {
			logger.Info("清理遗留 PVC（数据安全：只删本 CR 标签的）")
			var pvcs corev1.PersistentVolumeClaimList
			if err := r.List(ctx, &pvcs, client.InNamespace(db.Namespace),
				client.MatchingLabels{"app.kubernetes.io/managed-by": "mysql-operator"}); err == nil {
				for i := range pvcs.Items {
					logger.Info("删除 PVC", "name", pvcs.Items[i].Name)
					_ = r.Delete(ctx, &pvcs.Items[i])
				}
			}
			controllerutil.RemoveFinalizer(&db, mysqlFinalizer)
			if err := r.Update(ctx, &db); err != nil {
				return ctrl.Result{}, err
			}
		}
		return ctrl.Result{}, nil
	}

	// ---- 幂等补 Finalizer ----
	if controllerutil.AddFinalizer(&db, mysqlFinalizer) {
		return ctrl.Result{Requeue: true}, r.Update(ctx, &db)
	}

	// ---- 1. Headless Service（StatefulSet 稳定网络标识）----
	hsvc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: db.Name + "-h", Namespace: db.Namespace, Labels: mysqlLabels(db.Name)},
		Spec: corev1.ServiceSpec{
			ClusterIP:                "None",
			Selector:                 mysqlLabels(db.Name),
			Ports:                    []corev1.ServicePort{{Name: "mysql", Port: 3306}},
			PublishNotReadyAddresses: true,
		},
	}
	if err := createOrUpdate(ctx, r.Client, hsvc, &db, r.Scheme, func() error {
		hsvc.Spec.Selector = mysqlLabels(db.Name)
		return nil
	}); err != nil {
		return ctrl.Result{}, fmt.Errorf("headless svc: %w", err)
	}

	// ---- 2. ClusterIP Service ----
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: db.Name, Namespace: db.Namespace, Labels: mysqlLabels(db.Name)},
		Spec: corev1.ServiceSpec{
			Selector: mysqlLabels(db.Name),
			Ports:    []corev1.ServicePort{{Name: "mysql", Port: 3306}},
		},
	}
	if err := createOrUpdate(ctx, r.Client, svc, &db, r.Scheme, func() error {
		svc.Spec.Selector = mysqlLabels(db.Name)
		return nil
	}); err != nil {
		return ctrl.Result{}, fmt.Errorf("svc: %w", err)
	}

	// ---- 3. StatefulSet ----
	sts := r.desiredStatefulSet(&db)
	if err := controllerutil.SetControllerReference(&db, sts, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}
	// 给 VCT 产出的 PVC 打管理标签，Finalizer 清理时按标签匹配
	for i := range sts.Spec.VolumeClaimTemplates {
		sts.Spec.VolumeClaimTemplates[i].Labels = mysqlLabels(db.Name)
	}
	if err := createOrUpdate(ctx, r.Client, sts, &db, r.Scheme, func() error {
		sts.Spec.Replicas = dbReplicas()
		sts.Spec.Template = r.mysqlPodTemplate(&db)
		return controllerutil.SetControllerReference(&db, sts, r.Scheme)
	}); err != nil {
		return ctrl.Result{}, fmt.Errorf("statefulset: %w", err)
	}

	// ---- 4. 备份 CronJob（可选，backupSchedule 留空 = 不备份）----
	var cronName string
	if db.Spec.BackupSchedule != "" {
		// 备份 PVC 必须由 controller 显式创建（CronJob 的卷引用不会触发动态供给）
		backupPVC := &corev1.PersistentVolumeClaim{
			ObjectMeta: metav1.ObjectMeta{Name: db.Name + "-backup", Namespace: db.Namespace, Labels: mysqlLabels(db.Name)},
			Spec: corev1.PersistentVolumeClaimSpec{
				AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
				Resources: corev1.VolumeResourceRequirements{Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse("1Gi"),
				}},
			},
		}
		if err := createOrUpdate(ctx, r.Client, backupPVC, &db, r.Scheme, func() error { return nil }); err != nil {
			return ctrl.Result{}, fmt.Errorf("backup pvc: %w", err)
		}
		cron := r.desiredBackupCronJob(&db)
		if err := controllerutil.SetControllerReference(&db, cron, r.Scheme); err != nil {
			return ctrl.Result{}, err
		}
		if err := createOrUpdate(ctx, r.Client, cron, &db, r.Scheme, func() error {
			cron.Spec.Schedule = db.Spec.BackupSchedule
			return controllerutil.SetControllerReference(&db, cron, r.Scheme)
		}); err != nil {
			return ctrl.Result{}, err
		}
		cronName = cron.Name
	}

	// ---- 5. 状态回写 ----
	var stsLive appsv1.StatefulSet
	if err := r.Get(ctx, types.NamespacedName{Namespace: db.Namespace, Name: db.Name}, &stsLive); err != nil {
		return ctrl.Result{}, err
	}
	ready := stsLive.Status.ReadyReplicas > 0
	cond := metav1.Condition{
		Type: "Ready", ObservedGeneration: db.Generation, LastTransitionTime: metav1.Now(),
		Reason: "WaitingForReplicas", Message: fmt.Sprintf("%d/%d 副本 Ready", stsLive.Status.ReadyReplicas, 1),
		Status: metav1.ConditionFalse,
	}
	if ready {
		cond.Status = metav1.ConditionTrue
		cond.Reason = "StatefulSetReady"
	}
	changed := !meta.IsStatusConditionPresentAndEqual(db.Status.Conditions, cond.Type, cond.Status) ||
		db.Status.ObservedGeneration != db.Generation || db.Status.BackupCronJobName != cronName
	meta.SetStatusCondition(&db.Status.Conditions, cond)
	db.Status.ObservedGeneration = db.Generation
	db.Status.BackupCronJobName = cronName
	if changed {
		if err := r.Status().Update(ctx, &db); err != nil {
			return ctrl.Result{}, err
		}
	}

	logger.Info("调谐完成", "ready", ready, "backupCron", cronName)
	return ctrl.Result{}, nil
}

// desiredStatefulSet: mysql:8.0 单副本，数据 PVC 走 volumeClaimTemplates，
// 备份 PVC 单独建（RWO，只给备份 CronJob 挂）
func (r *MySQLReconciler) desiredStatefulSet(db *mysqlv1.MySQL) *appsv1.StatefulSet {
	size := resource.MustParse(db.Spec.StorageSize)
	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: db.Name, Namespace: db.Namespace, Labels: mysqlLabels(db.Name)},
		Spec: appsv1.StatefulSetSpec{
			ServiceName:         db.Name + "-h",
			Replicas:            dbReplicas(),
			Selector:            &metav1.LabelSelector{MatchLabels: mysqlLabels(db.Name)},
			PodManagementPolicy: appsv1.OrderedReadyPodManagement,
			Template:            r.mysqlPodTemplate(db),
			VolumeClaimTemplates: []corev1.PersistentVolumeClaim{{
				ObjectMeta: metav1.ObjectMeta{Name: "data", Labels: mysqlLabels(db.Name)},
				Spec: corev1.PersistentVolumeClaimSpec{
					AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
					Resources: corev1.VolumeResourceRequirements{Requests: corev1.ResourceList{
						corev1.ResourceStorage: size,
					}},
					StorageClassName: dbStorageClassPtr(),
				},
			}},
		},
	}
}

func (r *MySQLReconciler) mysqlPodTemplate(db *mysqlv1.MySQL) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{Labels: mysqlLabels(db.Name)},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{
				Name:  "mysql",
				Image: "mysql:8.0",
				Ports: []corev1.ContainerPort{{Name: "mysql", ContainerPort: 3306}},
				Env: []corev1.EnvVar{
					{Name: "MYSQL_ROOT_PASSWORD", ValueFrom: &corev1.EnvVarSource{
						SecretKeyRef: &corev1.SecretKeySelector{
							LocalObjectReference: corev1.LocalObjectReference{Name: db.Spec.RootPasswordSecret.Name},
							Key:                  db.Spec.RootPasswordSecret.Key,
						},
					}},
				},
				VolumeMounts: []corev1.VolumeMount{{Name: "data", MountPath: "/var/lib/mysql"}},
			}},
		},
	}
}

// desiredBackupCronJob: mysqldump 全库 → 写入独立备份 PVC
func (r *MySQLReconciler) desiredBackupCronJob(db *mysqlv1.MySQL) *batchv1.CronJob {
	return &batchv1.CronJob{
		ObjectMeta: metav1.ObjectMeta{Name: db.Name + "-backup", Namespace: db.Namespace, Labels: mysqlLabels(db.Name)},
		Spec: batchv1.CronJobSpec{
			Schedule:                   db.Spec.BackupSchedule,
			ConcurrencyPolicy:          batchv1.ForbidConcurrent, // 备份绝不允许重叠
			SuccessfulJobsHistoryLimit: &[]int32{3}[0],
			FailedJobsHistoryLimit:     &[]int32{1}[0],
			JobTemplate: batchv1.JobTemplateSpec{
				Spec: batchv1.JobSpec{
					BackoffLimit: &[]int32{1}[0],
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							RestartPolicy: corev1.RestartPolicyNever,
							Containers: []corev1.Container{{
								Name:    "backup",
								Image:   "mysql:8.0",
								Command: []string{"/bin/sh", "-c"},
								Args: []string{
									"mysqldump -h " + db.Name + " -uroot -p\"$MYSQL_ROOT_PASSWORD\" --all-databases | gzip > /backup/dump-$(date +%Y%m%d-%H%M).sql.gz && echo backup-ok",
								},
								Env: []corev1.EnvVar{
									{Name: "MYSQL_ROOT_PASSWORD", ValueFrom: &corev1.EnvVarSource{
										SecretKeyRef: &corev1.SecretKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: db.Spec.RootPasswordSecret.Name},
											Key:                  db.Spec.RootPasswordSecret.Key,
										},
									}},
								},
								VolumeMounts: []corev1.VolumeMount{{Name: "backup", MountPath: "/backup"}},
							}},
							Volumes: []corev1.Volume{{
								Name: "backup",
								VolumeSource: corev1.VolumeSource{
									PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
										ClaimName: db.Name + "-backup",
									},
								},
							}},
						},
					},
				},
			},
		},
	}
}

func createOrUpdate(ctx context.Context, c client.Client, obj client.Object, owner *mysqlv1.MySQL, scheme *runtime.Scheme, mutate func() error) error {
	if err := controllerutil.SetControllerReference(owner, obj, scheme); err != nil {
		return err
	}
	op, err := controllerutil.CreateOrPatch(ctx, c, obj, func() error {
		if err := mutate(); err != nil {
			return err
		}
		return controllerutil.SetControllerReference(owner, obj, scheme)
	})
	logf.FromContext(ctx).V(1).Info("reconciled", "kind", obj.GetObjectKind().GroupVersionKind().Kind, "op", string(op))
	return err
}

func mysqlLabels(name string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       name,
		"app.kubernetes.io/managed-by": "mysql-operator",
	}
}

func dbReplicas() *int32         { r := int32(1); return &r }
func dbStorageClassPtr() *string { return nil } // 用集群默认 SC（kind 的 standard）

// SetupWithManager sets up the controller with the Manager.
// Owns()：StatefulSet / CronJob / Service 变化（含被手改）都会触发调谐。
func (r *MySQLReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&mysqlv1.MySQL{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&batchv1.CronJob{}).
		Owns(&corev1.Service{}).
		Named("mysql").
		Complete(r)
}
