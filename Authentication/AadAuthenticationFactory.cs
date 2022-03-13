using Microsoft.Identity.Client;
using System;
using System.Linq;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.Identity.Authentication
{
    /// <summary>
    /// Public client supported authentication flows
    /// </summary>
    public enum AuthenticationMode
    {
        Interactive,
        DeviceCode,
    }

    /// <summary>
    /// Type of client we use for auth
    /// </summary>
    enum AuthenticationFlow
    {
        PublicClient,
        ConfidentialClient
    }

    /// <summary>
    /// Common wrapper class for various authentication flows
    /// </summary>
    public class AadAuthenticationFactory
    {
        private readonly string _clientId;
        private readonly string _loginApi;
        private readonly string[] _scopes;
        private readonly AuthenticationMode _authMode;
        private readonly AuthenticationFlow _flow;
        private readonly string _userNameHint;

        private IPublicClientApplication _publicClientApplication;
        private IConfidentialClientApplication _confidentialClientApplication;
        /// <summary>
        /// Creates factory that supporrts Public client flows with Interactive or DeviceCode authentication
        /// </summary>
        /// <param name="tenantId">DNS name or Id of tenant that authenticates user</param>
        /// <param name="clientId">ClientId to use</param>
        /// <param name="scopes">List of scopes that clients asks for</param>
        /// <param name="loginApi">AAD endpoint that will handle the authentication.</param>
        /// <param name="authenticationMode">Type of public client flow to use</param>
        /// <param name="userNameHint">Which username to use in auth UI in case there may be multiple names available</param>
        public AadAuthenticationFactory(
            
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

        /// <summary>
        /// Creates factory that supporrts Confidential client flows with ClientSecret authentication
        /// <param name="tenantId">DNS name or Id of tenant that authenticates user</param>
        /// <param name="clientId">ClientId to use</param>
        /// <param name="scopes">List of scopes that clients asks for</param>
        /// <param name="loginApi">AAD endpoint that will handle the authentication.</param>
        /// <param name="clientSecret">Client secret to be used</param>
        public AadAuthenticationFactory(
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

        /// <summary>
        /// Creates factory that supporrts Confidential client flows with X509 certificate authentication
        /// <param name="tenantId">DNS name or Id of tenant that authenticates user</param>
        /// <param name="clientId">ClientId to use</param>
        /// <param name="scopes">List of scopes that clients asks for</param>
        /// <param name="loginApi">AAD endpoint that will handle the authentication.</param>
        /// <param name="clientCertificate">Client secret to be used</param>
        public AadAuthenticationFactory(
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

        /// <summary>
        /// Authenticates caller based on configuration provided in constructor.
        /// </summary>
        /// <returns>AuthenticationResult that contains tokens and other information</returns>
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
                                throw new ArgumentException($"Unsupported Public client authentication mode: {_authMode}");
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
