using Microsoft.Identity.Client;
using System;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.Identity.Authentication
{
    public class AadAuthenticationFactory
    {
        private readonly string _clientId;
        private readonly string _loginApi;
        private readonly string[] _scopes;
        private readonly AuthenticationMode _authMode;
        private readonly AuthenticationFlow _flow;
        private readonly string _userNameHint;

        private readonly IPublicClientApplication _publicClientApplication;
        private readonly IConfidentialClientApplication _confidentialClientApplication;
        private readonly ManagedIdentityClientApplication _managedIdentityClientApplication;
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

            var builder = PublicClientApplicationBuilder.Create(_clientId)
                .WithDefaultRedirectUri()
                .WithAuthority($"{_loginApi}/{tenantId}")
                .WithHttpClientFactory(new GcMsalHttpClientFactory());
            

            _publicClientApplication = builder.Build();
        }

        /// <summary>
        /// Creates factory that supporrts Confidential client flows with ClientSecret authentication
        /// </summary>
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


            var builder = ConfidentialClientApplicationBuilder.Create(_clientId)
                .WithClientSecret(clientSecret)
                .WithAuthority($"{_loginApi}/{tenantId}")
                .WithHttpClientFactory(new GcMsalHttpClientFactory());

            _confidentialClientApplication = builder.Build();
        }

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

            var builder = ConfidentialClientApplicationBuilder.Create(_clientId)
                .WithCertificate(clientCertificate)
                .WithAuthority($"{_loginApi}/{tenantId}");

            _confidentialClientApplication = builder.Build();
        }

        /// <summary>
        /// Creates factory that supports ManagedIdentity authentication
        /// </summary>
        /// <param name="scopes">Required scopes to obtain. Currently obtains all assigned scopes for first resource in the array.</param>
        public AadAuthenticationFactory(string[] scopes)
        {
            _scopes = scopes;
            _managedIdentityClientApplication = new ManagedIdentityClientApplication(new GcMsalHttpClientFactory());
            _flow = AuthenticationFlow.ManagedIdentity;

        }

        /// <summary>
        /// Creates factory that supports UserAssignedIdentity authentication
        /// </summary>
        /// <param name="clientId">AppId of User Assigned Identity</param>
        /// <param name="scopes">Required scopes to obtain. Currently obtains all assigned scopes for first resource in the array.</param>
        public AadAuthenticationFactory(string clientId, string[] scopes)
        {
            _scopes = scopes;
            _clientId = clientId;
            _managedIdentityClientApplication = new ManagedIdentityClientApplication(new GcMsalHttpClientFactory());
            _flow = AuthenticationFlow.UserAssignedIdentity;
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
