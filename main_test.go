package main

import (
	"os"
	"testing"
	"time"

	acmetest "github.com/cert-manager/cert-manager/test/acme"
	"github.com/struassel/cert-manager-webhook-desec/desec"
)

var (
	zone = os.Getenv("TEST_ZONE_NAME")
)

func TestRunsSuite(t *testing.T) {
	// The manifest path should contain a file named config.json that is a
	// snippet of valid configuration that should be included on the
	// ChallengeRequest passed as part of the test cases.
	//

	//domain := ""
	//if len(zone) > 0 {
	//	domain = zone[:len(zone)-1]
	//}

	fixture := acmetest.NewFixture(desec.NewDesecDnsSolver(),
		acmetest.SetResolvedZone(zone),
		//acmetest.SetDNSName(domain),
		//acmetest.SetResolvedFQDN("_acme-challenge."+zone),
		acmetest.SetAllowAmbientCredentials(false),
		acmetest.SetManifestPath("testdata/desec-solver"),
		//Sometimes propagation is slow
		acmetest.SetPropagationLimit(15*time.Minute),
	)
	//solver := example.New("59351")
	//fixture := acmetest.NewFixture(solver,
	//	acmetest.SetResolvedZone("example.com."),
	//	acmetest.SetManifestPath("testdata/my-custom-solver"),
	//	acmetest.SetDNSServer("127.0.0.1:59351"),
	//	acmetest.SetUseAuthoritative(false),
	//)
	//need to uncomment and  RunConformance delete runBasic and runExtended once https://github.com/cert-manager/cert-manager/pull/4835 is merged
	//fixture.RunConformance(t)
	fixture.RunBasic(t)
	fixture.RunExtended(t)

}
