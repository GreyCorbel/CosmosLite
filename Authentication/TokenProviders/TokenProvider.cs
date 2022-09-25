using Microsoft.Identity.Client;
using System;
using System.Security.Claims;
using System.Security.Principal;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.Identity.Authentication
{
    internal abstract class TokenProvider : ITokenProvider
    {
        protected static string IdentityEndpoint => Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT");
        protected static string IdentityHeader => Environment.GetEnvironmentVariable("IDENTITY_HEADER");
        protected static string MsiEndpoint => Environment.GetEnvironmentVariable("MSI_ENDPOINT");
        protected static string MsiSecret => Environment.GetEnvironmentVariable("MSI_SECRET");
        protected static string ImdsEndpoint => Environment.GetEnvironmentVariable("IMDS_ENDPOINT");
        public static string ApiVersion => "2020-06-01";
        protected static string SecretHeaderName => "X-IDENTITY-HEADER";
        protected static string ClientIdHeaderName => "client_id";

        protected IMsalHttpClientFactory _httpClientFactory;
        protected readonly string _clientId = null;

        protected readonly int _ticketOverlapSeconds = 300;

        public TokenProvider(IMsalHttpClientFactory factory, string clientId = null)
        {
            _httpClientFactory = factory;
            _clientId = clientId;
        }
        public abstract Task<AuthenticationResult> AcquireTokenForClientAsync(string[] scopes, CancellationToken cancellationToken);

        protected AuthenticationResult CreateAuthenticationResult(ManagedIdentityAuthenticationResponse authResponse)
        {
            long.TryParse(authResponse.expires_on,  out long expiresOn);
            DateTimeOffset tokenExpiresOn = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(expiresOn);
            ClaimsPrincipal principal = null;
            if(!string.IsNullOrEmpty(authResponse.client_id))
            {
                principal = new();
                GenericIdentity identity = new(authResponse.client_id, "aad");
                principal.AddIdentity(new ClaimsIdentity(identity));
            }

            Guid tokenId = Guid.NewGuid();
            return new AuthenticationResult(
                authResponse.access_token,
                false,
                tokenId.ToString(),
                tokenExpiresOn,
                tokenExpiresOn,
                null,
                null,
                null,
                ScopeHelper.ResourceToScope(authResponse.resource),
                tokenId,
                authResponse.token_type,
                null,
                principal
                );
        }
    }
}
