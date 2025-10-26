package desec

import (
	"context"
	"fmt"
	"log"
	"slices"

	"github.com/cert-manager/cert-manager/pkg/acme/webhook"
	"github.com/cert-manager/cert-manager/pkg/acme/webhook/apis/acme/v1alpha1"

	"github.com/go-acme/lego/v4/challenge/dns01"
	"github.com/nrdcg/desec"
	"github.com/pkg/errors"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
)

// desecDnsSolver implements the provider-specific logic needed to
// 'present' an ACME challenge TXT record for your own DNS provider.
// To do so, it must implement the `github.com/cert-manager/cert-manager/pkg/acme/webhook.Solver`
// interface.
type desecDnsSolver struct {
	// 4. ensure your webhook's service account has the required RBAC role
	//    assigned to it for interacting with the Kubernetes APIs you need.
	client *kubernetes.Clientset
}

func NewDesecDnsSolver() webhook.Solver {
	return &desecDnsSolver{}
}

// Name is used as the name for this DNS solver when referencing it on the ACME
// Issuer resource.
// This should be unique **within the group name**, i.e. you can have two
// solvers configured with the same Name() **so long as they do not co-exist
// within a single webhook deployment**.
// For example, `cloudflare` may be used as the name of a solver.
func (s *desecDnsSolver) Name() string {
	return "desec-solver"
}

func (s *desecDnsSolver) getToken(context context.Context, cfg *DesecConfig, namespace string) (*string, error) {
	name := cfg.APITokenRef.LocalObjectReference.Name
	key := cfg.APITokenRef.Key
	secret, err := s.client.CoreV1().Secrets(namespace).Get(context, name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to load secret \"%s/%s\": %w", namespace, name, err)
	}

	data, ok := secret.Data[key]
	if !ok {
		return nil, fmt.Errorf("key %s not found in secret \"%s/%s\"", key, namespace, name)
	}

	token := string(data)
	return &token, nil
}

func (s *desecDnsSolver) getClient(context context.Context, cfg *DesecConfig, namespace string) (*desec.Client, error) {
	token, err := s.getToken(context, cfg, namespace)
	if err != nil {
		return nil, fmt.Errorf("cannot obtain token: %w", err)
	}

	opts := desec.NewDefaultClientOptions()
	opts.Logger = log.Default()
	return desec.New(*token, opts), nil
}

// Present is responsible for actually presenting the DNS record with the
// DNS provider.
// This method should tolerate being called multiple times with the same value.
// cert-manager itself will later perform a self check to ensure that the
// solver has correctly configured the DNS provider.
func (s *desecDnsSolver) Present(ch *v1alpha1.ChallengeRequest) error {
	klog.Infof("Presenting TXT record: DNSName=%s, FDQN=%s, Zone=%s", ch.DNSName, ch.ResolvedFQDN, ch.ResolvedZone)
	ctx := context.Background()
	cfg, err := loadConfig(ch.Config)
	if err != nil {
		return fmt.Errorf("cannot load config: %w", err)
	}

	klog.Infof("Obtaining desec client")
	client, err := s.getClient(ctx, &cfg, ch.ResourceNamespace)
	if err != nil {
		return fmt.Errorf("error obtaining desec client for domain %s: %w", ch.DNSName, err)
	}

	fqdn := dns01.UnFqdn(ch.ResolvedFQDN)
	zone := dns01.UnFqdn(ch.ResolvedZone)
	value := fmt.Sprintf(`%q`, ch.Key)
	subdomain := ""

	if zone != fqdn {
		subdomain, err = dns01.ExtractSubDomain(fqdn, zone)
		if err != nil {
			return fmt.Errorf("cannot extract subdomain from %s: %w", fqdn, err)
		}
	}

	klog.Infof("Obtaining TXT records for %s", fqdn)
	rrSet, err := client.Records.Get(ctx, zone, subdomain, "TXT")
	if err != nil {
		var nf *desec.NotFoundError
		if !errors.As(err, &nf) {
			return fmt.Errorf("failed to get TXT records for %s: %w", fqdn, err)
		}

		klog.Infof("Creating TXT record for %s", fqdn)
		// Not found case -> create
		_, err = client.Records.Create(ctx, desec.RRSet{
			Domain:  zone,
			SubName: subdomain,
			Type:    "TXT",
			Records: []string{value},
			TTL:     3600,
		})

		if err != nil {
			return fmt.Errorf("failed to create TXT record for %s: %w", fqdn, err)
		}

		klog.Infof("TXT record successfully created for domain %s", fqdn)
		return nil
	}

	klog.Infof("Updating TXT record for %s", fqdn)
	var records []string
	if slices.Contains(rrSet.Records, value) {
		records = rrSet.Records
	} else {
		records = append(rrSet.Records, value)
	}

	_, err = client.Records.Update(ctx, zone, subdomain, "TXT", desec.RRSet{Records: records})
	if err != nil {
		return fmt.Errorf("failed to update TXT record for %s: %w", fqdn, err)
	}

	klog.Infof("TXT record successfully added for %s", fqdn)
	return nil
}

// CleanUp should delete the relevant TXT record from the DNS provider console.
// If multiple TXT records exist with the same record name (e.g.
// _acme-challenge.example.com) then **only** the record with the same `key`
// value provided on the ChallengeRequest should be cleaned up.
// This is in order to facilitate multiple DNS validations for the same domain
// concurrently.
func (s *desecDnsSolver) CleanUp(ch *v1alpha1.ChallengeRequest) error {
	klog.Infof("Cleaning TXT record: DNSName=%s, FDQN=%s, Zone=%s", ch.DNSName, ch.ResolvedFQDN, ch.ResolvedZone)
	ctx := context.Background()
	cfg, err := loadConfig(ch.Config)
	if err != nil {
		return fmt.Errorf("cannot load config: %w", err)
	}

	klog.Infof("Obtaining desec client")
	client, err := s.getClient(ctx, &cfg, ch.ResourceNamespace)
	if err != nil {
		return fmt.Errorf("error obtaining desec client for domain %s: %w", ch.DNSName, err)
	}

	fqdn := dns01.UnFqdn(ch.ResolvedFQDN)
	zone := dns01.UnFqdn(ch.ResolvedZone)
	value := fmt.Sprintf(`%q`, ch.Key)
	subdomain := ""

	if zone != fqdn {
		subdomain, err = dns01.ExtractSubDomain(fqdn, zone)
		if err != nil {
			return fmt.Errorf("cannot extract subdomain from %s: %w", fqdn, err)
		}
	}

	klog.Infof("Obtaining TXT records for %s", fqdn)
	rrSet, err := client.Records.Get(ctx, zone, subdomain, "TXT")
	if err != nil {
		return fmt.Errorf("failed to get TXT record for %s: %w", fqdn, err)
	}

	records := slices.DeleteFunc(rrSet.Records, func(s string) bool {
		return s == value
	})

	if len(records) == 0 {
		err = client.Records.Delete(ctx, zone, subdomain, "TXT")
		if err != nil {
			return fmt.Errorf("failed to delete TXT record for %s: %w", fqdn, err)
		}
	} else {
		_, err = client.Records.Update(ctx, zone, subdomain, "TXT", desec.RRSet{Records: records})
		if err != nil {
			return fmt.Errorf("failed to update TXT record for %s: %w", fqdn, err)
		}
	}

	klog.Infof("TXT record successfully cleaned for %s", fqdn)
	return nil
}

// Initialize will be called when the webhook first starts.
// This method can be used to instantiate the webhook, i.e. initialising
// connections or warming up caches.
// Typically, the kubeClientConfig parameter is used to build a Kubernetes
// client that can be used to fetch resources from the Kubernetes API, e.g.
// Secret resources containing credentials used to authenticate with DNS
// provider accounts.
// The stopCh can be used to handle early termination of the webhook, in cases
// where a SIGTERM or similar signal is sent to the webhook process.
func (s *desecDnsSolver) Initialize(kubeClientConfig *rest.Config, stopCh <-chan struct{}) error {
	klog.Info("Loading configuration")
	cl, err := kubernetes.NewForConfig(kubeClientConfig)
	if err != nil {
		return err
	}

	s.client = cl
	klog.Info("Solver initialized")
	return nil
}
