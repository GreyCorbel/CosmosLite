using Microsoft.Identity.Client;
using System;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.Identity.Authentication
{
    /// <summary>
    /// Main object responsible for authentication according to constructor and parameters used
    /// </summary>
    public class AadAuthenticationFactory
    {
        /// <summary>
        /// Tenant Id of AAD tenant that authenticates the user / app
        /// </summary>
        public string TenantId { get { return _tenantId; } }
        private readonly string _tenantId;
        /// <summary>
        /// ClientId to be used for authentication flows
        /// </summary>
        public string ClientId {get {return _clientId;}}
        private readonly string _clientId;
        /// <summary>
        /// AAD authorization endpoint. Defaults to public AAD
        /// </summary>
        public string LoginApi {get {return _loginApi;}}
        private readonly string _loginApi;

        /// <summary>
        /// Scopes the factory asks for when asking for tokens
        /// </summary>
        public string[] Scopes {get {return _scopes;}}
        private readonly string[] _scopes;
        
        //type of auth flow to use
        private readonly AuthenticationFlow _flow;

        /// <summary>
        /// UserName hint to use in authentication flows to help select proper user. Useful in case multiple accounts are logged in.
        /// </summary>
        public string UserName { get { return _userNameHint; } }
        private readonly string _userNameHint;

        /// <summary>
        /// Password for ROPC flow
        /// </summary>
        private readonly SecureString _resourceOwnerPassword;

        private readonly IPublicClientApplication _publicClientApplication;
        private readonly IConfidentialClientApplication _confidentialClientApplication;
        private readonly ManagedIdentityClientApplication _managedIdentityClientApplication;
        private readonly string _defaultClientId = "1950a258-227b-4e31-a9cf-717495945fc2";

        /// <summary>
        /// Creates factory that supporrts Public client flows with Interactive or DeviceCode authentication
        /// </summary>
        /// <param name="tenantId">DNS name or Id of tenant that authenticates user</param>
        /// <param name="clientId">ClientId to use. If not specified, clientId of Azure Powershell is used</param>
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
            if (string.IsNullOrWhiteSpace(clientId))
                _clientId = _defaultClientId;
            else
                _clientId = clientId;

            _loginApi = loginApi;
            _scopes = scopes;
            _userNameHint = userNameHint;
            _tenantId = tenantId;

            switch(authenticationMode)
            {
                case AuthenticationMode.WIA:
                    _flow = AuthenticationFlow.PublicClientWithWia;
                    break;
                case AuthenticationMode.DeviceCode:
                    _flow = AuthenticationFlow.PublicClientWithDeviceCode;
                    break;
                default:
                    _flow = AuthenticationFlow.PublicClient;
                    break;
            }

            var builder = PublicClientApplicationBuilder.Create(_clientId)
                .WithDefaultRedirectUri()
                .WithAuthority($"{_loginApi}/{tenantId}")
                .WithHttpClientFactory(new GcMsalHttpClientFactory());

            _publicClientApplication = builder.Build();
        }

        /// <summary>
        /// Creates factory that supports Confidential client flows via MSAL with ClientSecret authentication
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

        /// <summary>
        /// Constructor for Confidential client authentication flow via MSAL and X509 certificate authentication
        /// </summary>
        /// <param name="tenantId">Dns domain name or tenant guid</param>
        /// <param name="clientId">Client id that represents application asking for token</param>
        /// <param name="clientCertificate">X509 certificate with private key. Public part of certificate is expected to be registered with app registration for given client id in AAD.</param>
        /// <param name="scopes">Scopes application asks for</param>
        /// <param name="loginApi">AAD endpoint URL for special instance of AAD (/e.g. US Gov)</param>
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
                .WithAuthority($"{_loginApi}/{tenantId}")
                .WithHttpClientFactory(new GcMsalHttpClientFactory());

            _confidentialClientApplication = builder.Build();
        }

        /// <summary>
        /// Creates factory that supports UserAssignedIdentity authentication with provided client id
        /// </summary>
        /// <param name="clientId">AppId of User Assigned Identity</param>
        /// <param name="scopes">Required scopes to obtain. Currently obtains all assigned scopes for first resource in the array.</param>
        public AadAuthenticationFactory(string clientId, string[] scopes)
        {
            _scopes = scopes;
            if (!string.IsNullOrWhiteSpace(clientId))
            {
                _clientId = clientId;
            }
            else
            { 
                _clientId=null;
            }
            _managedIdentityClientApplication = new ManagedIdentityClientApplication(new GcMsalHttpClientFactory(), _clientId);
            _flow = AuthenticationFlow.UserAssignedIdentity;
        }

        /// <summary>
        /// Creates factory that supporrts Public client ROPC flow
        /// </summary>
        /// <param name="tenantId">DNS name or Id of tenant that authenticates user</param>
        /// <param name="clientId">ClientId to use</param>
        /// <param name="scopes">List of scopes that clients asks for</param>
        /// <param name="loginApi">AAD endpoint that will handle the authentication.</param>
        /// <param name="userName">Resource owner username and password</param>
        /// <param name="password">Resource owner password</param>
        public AadAuthenticationFactory(
            string tenantId,
            string clientId,
            string[] scopes,
            string userName,
            SecureString password,
            string loginApi = "https://login.microsoftonline.com"
            )
        {
            if (string.IsNullOrWhiteSpace(clientId))
                _clientId = _defaultClientId;
            else
                _clientId = clientId;

            _loginApi = loginApi;
            _scopes = scopes;
            _userNameHint = userName;
            _resourceOwnerPassword = password;
            _tenantId = tenantId;

            _flow = AuthenticationFlow.ResourceOwnerPassword;

            var builder = PublicClientApplicationBuilder.Create(_clientId)
                .WithDefaultRedirectUri()
                .WithAuthority($"{_loginApi}/{tenantId}")
                .WithHttpClientFactory(new GcMsalHttpClientFactory());

            _publicClientApplication = builder.Build();
        }

        /// <summary>
        /// Returns authentication result
        /// Microsoft says we should not instantiate directly - but how to achieve unified experience of caller without being able to return it?
        /// </summary>
        /// <returns cref="AuthenticationResult">Authentication result object either returned fropm MSAL libraries, or - for ManagedIdentity - constructed from Managed Identity endpoint response, as returned by cref="ManagedIdentityClientApplication.ApiVersion" version of endpoint</returns>
        /// <exception cref="ArgumentException">Throws if unsupported authentication mode or flow detected</exception>
        public async Task<AuthenticationResult> AuthenticateAsync(string[] requiredScopes = null)
        {
            using CancellationTokenSource cts = new(TimeSpan.FromMinutes(2));
            AuthenticationResult result;
            if (null == requiredScopes)
                requiredScopes = _scopes;
            switch(_flow)
            {
                case AuthenticationFlow.PublicClientWithWia:
                {
                        var accounts = await _publicClientApplication.GetAccountsAsync();
                        IAccount account;
                        if (string.IsNullOrWhiteSpace(_userNameHint))
                            account = accounts.FirstOrDefault();
                        else
                            account = accounts.Where(x => string.Compare(x.Username, _userNameHint, true) == 0).FirstOrDefault();
                        if (null!=account)
                        {
                            result = await _publicClientApplication.AcquireTokenSilent(requiredScopes, account)
                                .ExecuteAsync();
                        }
                        else
                        {
                            result = await _publicClientApplication.AcquireTokenByIntegratedWindowsAuth(_scopes)
                                .ExecuteAsync(cts.Token);
                            //let the app throw to caller when UI required as the purpose here is to stay silent
                        }
                        return result;
                }
                //public client flow
                case AuthenticationFlow.PublicClient:
                    {
                        var accounts = await _publicClientApplication.GetAccountsAsync();
                        IAccount account;
                        if (string.IsNullOrWhiteSpace(_userNameHint))
                            account = accounts.FirstOrDefault();
                        else
                            account = accounts.Where(x => string.Compare(x.Username, _userNameHint, true) == 0).FirstOrDefault();
                        try
                        {
                            result = await _publicClientApplication.AcquireTokenSilent(requiredScopes, account)
                                              .ExecuteAsync(cts.Token);
                        }
                        catch (MsalUiRequiredException)
                        {
                            result = await _publicClientApplication.AcquireTokenInteractive(requiredScopes).ExecuteAsync(cts.Token);
                        }
                        return result;
                    }
                case AuthenticationFlow.PublicClientWithDeviceCode:
                    {
                        var accounts = await _publicClientApplication.GetAccountsAsync();
                        IAccount account;
                        if (string.IsNullOrWhiteSpace(_userNameHint))
                            account = accounts.FirstOrDefault();
                        else
                            account = accounts.Where(x => string.Compare(x.Username, _userNameHint, true) == 0).FirstOrDefault();
                        try
                        {
                            result = await _publicClientApplication.AcquireTokenSilent(requiredScopes, account)
                                              .ExecuteAsync(cts.Token);
                        }
                        catch (MsalUiRequiredException)
                        {
                            result = await _publicClientApplication.AcquireTokenWithDeviceCode(requiredScopes, callback =>
                                {
                                    Console.WriteLine(callback.Message);
                                    return Task.FromResult(0);
                                }).ExecuteAsync(cts.Token);
                        }
                        return result;
                    }
                case AuthenticationFlow.ConfidentialClient:
                    return await _confidentialClientApplication.AcquireTokenForClient(requiredScopes).ExecuteAsync(cts.Token);
                //System Managed identity
                case AuthenticationFlow.ManagedIdentity:
                    return await _managedIdentityClientApplication.AcquireTokenForClientAsync(requiredScopes, cts.Token);
                //User managed identity
                case AuthenticationFlow.UserAssignedIdentity:
                    return await _managedIdentityClientApplication.AcquireTokenForClientAsync(requiredScopes, cts.Token);
                //ROPC flow
                case AuthenticationFlow.ResourceOwnerPassword:
                {
                    var accounts = await _publicClientApplication.GetAccountsAsync();
                    IAccount account;
                    if (string.IsNullOrWhiteSpace(_userNameHint))
                        account = accounts.FirstOrDefault();
                    else
                        account = accounts.Where(x => string.Compare(x.Username, _userNameHint, true) == 0).FirstOrDefault();

                    try
                    {
                        result = await _publicClientApplication.AcquireTokenSilent(requiredScopes, account)
                                            .ExecuteAsync(cts.Token);
                    }
                    catch (MsalUiRequiredException)
                    {
                        result = await _publicClientApplication.AcquireTokenByUsernamePassword(requiredScopes, _userNameHint, _resourceOwnerPassword).ExecuteAsync(cts.Token);
                    }
                    return result;
                }
            }

            throw new ArgumentException($"Unsupported authentication flow: {_flow}");
        }
    }
}
