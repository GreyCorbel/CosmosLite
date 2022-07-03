using Microsoft.Identity.Client;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;


namespace GreyCorbel.Identity.Authentication
{
    enum ManagedIdentityClientApplicationSpecialization
    {
        VM,
        AppService,
        Unknown
    }

#pragma warning disable CA1001 // Types that own disposable fields should be disposable
    // SemaphoreSlim only needs to be disposed when AvailableWaitHandle is called.
    class ManagedIdentityClientApplication
#pragma warning restore CA1001

    {
        static string IdentityEndpoint => Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT");
        static string IdentityHeader => Environment.GetEnvironmentVariable("IDENTITY_HEADER");
        public static string ApiVersion => "2019-08-01";
        static string SecretHeaderName => "X-IDENTITY-HEADER";
        static string ClientIdHeaderName => "client_id";

        readonly string _clientId = null;

        IMsalHttpClientFactory _httpClientFactory;

        AuthenticationResult _cachedToken = null;
        private readonly SemaphoreSlim _lock = new SemaphoreSlim(1, 1);

        private readonly ManagedIdentityClientApplicationSpecialization _specialization = ManagedIdentityClientApplicationSpecialization.Unknown;
        private readonly int _ticketOverlapSeconds = 300;

        public ManagedIdentityClientApplication(IMsalHttpClientFactory factory, string clientId = null)
        {
            _httpClientFactory = factory;
            _clientId = clientId;
            if (!string.IsNullOrEmpty(IdentityEndpoint) && !string.IsNullOrEmpty(IdentityHeader))
                _specialization = ManagedIdentityClientApplicationSpecialization.AppService;
            else
                _specialization = ManagedIdentityClientApplicationSpecialization.VM;
        }

        public async Task<AuthenticationResult> AcquireTokenForClient(string[] scopes, CancellationToken cancellationToken)
        {
            await _lock.WaitAsync().ConfigureAwait(false);

            try
            {
                if (null != _cachedToken && _cachedToken.ExpiresOn.UtcDateTime > DateTime.UtcNow.AddSeconds(_ticketOverlapSeconds))
                    return _cachedToken;

                //token not retrieved yet or about to expire --> get a new one
                var client = _httpClientFactory.GetHttpClient();
                using HttpRequestMessage message = CreateRequestMessage(scopes);

                using var response = await client.SendAsync(message, cancellationToken).ConfigureAwait(false);
                if (response.IsSuccessStatusCode)
                {
                    string payload = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    var authResponse = payload.FromJson<ManagedIdentityAuthenticationResponse>();
                    if (authResponse != null)
                    {
                        _cachedToken = CreateAuthenticationResult(authResponse);
                        return _cachedToken;
                    }
                    else
                        throw new FormatException($"Invalid authentication response received: {payload}");
                }
                else
                    throw new MsalClientException(response.StatusCode.ToString(), response.ReasonPhrase);
            }
            finally
            {
                _lock.Release();
            }
        }
        HttpRequestMessage CreateRequestMessage(string[] scopes)
        {
            using HttpRequestMessage message = new HttpRequestMessage();
            message.Method = HttpMethod.Get;
            StringBuilder sb;

            switch (_specialization)
            {
                case ManagedIdentityClientApplicationSpecialization.AppService:

                    sb = new StringBuilder(IdentityEndpoint);
                    message.Headers.Add(SecretHeaderName, IdentityHeader);
                    break;

                case ManagedIdentityClientApplicationSpecialization.VM:
                    sb = new StringBuilder("http://169.254.169.254/metadata/identity/oauth2/token");
                    break;
                default:
                    throw new InvalidOperationException("ManagedIdentityClientApplication: We're running in unsupported or unrecognized environment");
            }

            //the same for all types so far
            sb.Append($"?api-version={Uri.EscapeDataString(ApiVersion)}");
            sb.Append($"&resource={Uri.EscapeDataString(ScopeHelper.ScopeToResource(scopes))}");

            if (!string.IsNullOrEmpty(_clientId))
            {
                sb.Append($"client_id={Uri.EscapeDataString(_clientId)}");
                sb.Append("&");
            }
            message.RequestUri = new Uri(sb.ToString());
            message.Headers.Add("Metadata", "true");
            return message;
        }
        /// <summary>
        /// Creates unified authentication response
        /// </summary>
        /// <param name="authResponse">Object representing response from internal identity endpoint</param>
        /// <returns></returns>
        AuthenticationResult CreateAuthenticationResult(ManagedIdentityAuthenticationResponse authResponse)
        {
            long tokenExpiresOn = long.Parse(authResponse.expires_on);
            DateTimeOffset tokenExpires = new DateTimeOffset(DateTime.UtcNow.AddSeconds(tokenExpiresOn));
            Guid tokenId = Guid.NewGuid();
            return new AuthenticationResult(
                authResponse.access_token,
                false,
                tokenId.ToString(),
                tokenExpires,
                tokenExpires,
                null,
                null,
                null,
                ScopeHelper.ResourceToScope(authResponse.resource),
                tokenId,
                authResponse.token_type
                );

        }
    }
}
