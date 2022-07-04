using Microsoft.Identity.Client;
using System;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.Identity.Authentication
{
    internal class AppServiceTokenProvider : TokenProvider
    {
        public AppServiceTokenProvider(IMsalHttpClientFactory factory, string clientId = null)
            : base(factory, clientId)
        {

        }

        public override async Task<AuthenticationResult> AcquireTokenForClientAsync(string[] scopes, CancellationToken cancellationToken)
        {
            var client = _httpClientFactory.GetHttpClient();
            using HttpRequestMessage message = CreateRequestMessage(scopes);

            using var response = await client.SendAsync(message, cancellationToken).ConfigureAwait(false);
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

        HttpRequestMessage CreateRequestMessage(string[] scopes)
        {
            using HttpRequestMessage message = new HttpRequestMessage();
            message.Method = HttpMethod.Get;
            StringBuilder sb= new StringBuilder(IdentityEndpoint);
            message.Headers.Add(SecretHeaderName, IdentityHeader);

            //the same for all types so far
            sb.Append($"?api-version={Uri.EscapeDataString(ApiVersion)}");
            sb.Append($"&resource={Uri.EscapeDataString(ScopeHelper.ScopeToResource(scopes))}");

            if (!string.IsNullOrEmpty(_clientId))
            {
                sb.Append($"&client_id={Uri.EscapeDataString(_clientId)}");
            }
            message.RequestUri = new Uri(sb.ToString());
            message.Headers.Add("Metadata", "true");
            return message;
        }
    }
}
