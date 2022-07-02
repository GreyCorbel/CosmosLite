using Microsoft.Identity.Client;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;


namespace GreyCorbel.Identity.Authentication
{
#pragma warning disable CA1001 // Types that own disposable fields should be disposable
    // SemaphoreSlim only needs to be disposed when AvailableWaitHandle is called.
    class ManagedIdentityClientApplication
#pragma warning restore CA1001

    {
        static string IdentityEndpoint => Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT");
        static string IdentityHeader => Environment.GetEnvironmentVariable("IDENTITY_HEADER");
        static string ApiVersion => "2019-08-01";
        static string SecretHeaderName => "X-IDENTITY-HEADER";
        static string ClientIdHeaderName => "client_id";

        readonly string _clientId = null;

        IMsalHttpClientFactory _httpClientFactory;

        AuthenticationResult _cachedToken = null;
        private readonly SemaphoreSlim _lock = new SemaphoreSlim(1, 1);

        public ManagedIdentityClientApplication(IMsalHttpClientFactory factory, string clientId = null)
        {
            _httpClientFactory = factory;
            _clientId = clientId;
        }

        public async Task<AuthenticationResult> AcquireTokenForClient(string[] scopes)
        {
            await _lock.WaitAsync().ConfigureAwait(false);

            try
            {
                if (null != _cachedToken && _cachedToken.ExpiresOn.UtcDateTime < DateTime.UtcNow.AddMinutes(-5))
                    return _cachedToken;

                //token not retrieved yet or about to expire --> get a new one
                var client = _httpClientFactory.GetHttpClient();

                //to build query
                StringBuilder sb = new StringBuilder(IdentityEndpoint);

                sb.Append("?");
                sb.Append($"resource={Uri.EscapeDataString(ScopeHelper.ScopeToResource(scopes))}");
                if (!string.IsNullOrEmpty(_clientId))
                    sb.Append($"&client_id={Uri.EscapeDataString(_clientId)}");
                sb.Append("&api-version={Uri.EscapeDataString(ApiVersion)}");

                using HttpRequestMessage message = new HttpRequestMessage(HttpMethod.Get, sb.ToString());
                message.Headers.Add(SecretHeaderName, IdentityHeader);
                message.Headers.Add("Metadata", "True");

                using var response = await client.SendAsync(message).ConfigureAwait(false);
                if (response.IsSuccessStatusCode)
                {
                    string payload = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    var authResponse = payload.FromJson<ManagedIdentityAuthenticationResponse>();
                    if (authResponse != null)
                    {
                        return CreateAuthenticationResult(authResponse);
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

        AuthenticationResult CreateAuthenticationResult(ManagedIdentityAuthenticationResponse authResponse)
        {
            DateTimeOffset tokenExpires = new DateTimeOffset(DateTime.UtcNow.AddSeconds(authResponse.expires_on));
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
