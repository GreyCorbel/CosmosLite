using Microsoft.Identity.Client;
using System;
using System.Linq;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.PublicClient.Authentication
{
    public enum AuthenticationMode
    {
        Interactive,
        DeviceCode,
    }

    enum AuthenticationFlow
    {
        PublicClient,
        ConfidentialClient
    }

    public class AuthenticationFactory
    {
        private readonly string _clientId;
        private readonly string _loginApi;
        private readonly string[] _scopes;
        private readonly AuthenticationMode _authMode;
        private readonly AuthenticationFlow _flow;
        private readonly string _userNameHint;

        private IPublicClientApplication _publicClientApplication;
        private IConfidentialClientApplication _confidentialClientApplication;
        public AuthenticationFactory(
            string tenantId, 
            string clientId, 
            string [] scopes, 
            string loginApi = "https://login.microsoftonline.com", 
            AuthenticationMode authenticationMode = AuthenticationMode.Interactive, 
            string userNameHint = null)
        {
            _clientId = clientId;
            _loginApi = loginApi;
            _scopes = scopes;
            _authMode = authenticationMode;
            _userNameHint = userNameHint;

            _flow = AuthenticationFlow.PublicClient;

            _publicClientApplication = PublicClientApplicationBuilder.Create(_clientId)
                .WithDefaultRedirectUri()
                .WithAuthority($"{_loginApi}/{tenantId}")
                .Build();
        }

        public AuthenticationFactory(
            string tenantId,
            string clientId,
            string clientSecret,
            string[] scopes,
            string loginApi = "https://login.microsoftonline.com")
        {
            _clientId = clientId;
            _loginApi = loginApi;
            _scopes = scopes;

            _flow = AuthenticationFlow.ConfidentialClient;

            _confidentialClientApplication = ConfidentialClientApplicationBuilder.Create(_clientId)
                .WithClientSecret(clientSecret)
                .WithAuthority($"{_loginApi}/{tenantId}")
                .Build();
        }

        public AuthenticationFactory(
            string tenantId,
            string clientId,
            X509Certificate2 clientCertificate,
            string[] scopes,
            string loginApi = "https://login.microsoftonline.com")
        {
            _clientId = clientId;
            _loginApi = loginApi;
            _scopes = scopes;

            _flow = AuthenticationFlow.ConfidentialClient;

            _confidentialClientApplication = ConfidentialClientApplicationBuilder.Create(_clientId)
                .WithCertificate(clientCertificate)
                .WithAuthority($"{_loginApi}/{tenantId}")
                .Build();
        }


        public async Task<AuthenticationResult> AuthenticateAsync()
        {
            using CancellationTokenSource cts = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            AuthenticationResult result;
            switch(_flow)
            {
                //public client flow
                case AuthenticationFlow.PublicClient:
                    var accounts = await _publicClientApplication.GetAccountsAsync();
                    IAccount account;
                    if (string.IsNullOrWhiteSpace(_userNameHint))
                        account = accounts.FirstOrDefault();
                    else
                        account = accounts.Where(x => string.Compare(x.Username, _userNameHint, true) == 0).FirstOrDefault();

                    try
                    {
                        result = await _publicClientApplication.AcquireTokenSilent(_scopes, account)
                                          .ExecuteAsync(cts.Token);
                    }
                    catch (MsalUiRequiredException)
                    {
                        switch (_authMode)
                        {
                            case AuthenticationMode.Interactive:
                                result = await _publicClientApplication.AcquireTokenInteractive(_scopes).ExecuteAsync(cts.Token);
                                break;
                            case AuthenticationMode.DeviceCode:
                                result = await _publicClientApplication.AcquireTokenWithDeviceCode(_scopes, callback =>
                                {
                                    Console.WriteLine(callback.Message);
                                    return Task.FromResult(0);
                                }).ExecuteAsync(cts.Token);
                                break;
                            default:
                                throw new ArgumentException($"Unsupported authentication mode: {_authMode}");
                        }
                    }
                    return result;

                case AuthenticationFlow.ConfidentialClient:
                    return await _confidentialClientApplication.AcquireTokenForClient(_scopes).ExecuteAsync(cts.Token);
            }

            throw new ArgumentException($"Unsupported authentication flow: {_flow}");

        }
    }
}
