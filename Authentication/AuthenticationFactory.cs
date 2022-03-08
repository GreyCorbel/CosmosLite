using Microsoft.Identity.Client;
using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace GreyCorbel.PublicClient.Authentication
{
    public enum AuthenticationMode
    {
        Interactive,
        DeviceCode
    }

    public class AuthenticationFactory
    {
        private readonly string _clientId;
        private readonly string _loginApi;
        private readonly string[] _scopes;

        private IPublicClientApplication _app;
        public AuthenticationFactory(string tenantId, string clientId, string [] scopes, string loginApi = "https://login.microsoftonline.com")
        {
            _clientId = clientId;
            _loginApi = loginApi;
            _scopes = scopes;
            _app = PublicClientApplicationBuilder.Create(_clientId)
                .WithDefaultRedirectUri()
                .WithAuthority($"{_loginApi}/{tenantId}")
                .Build();
        }

        public async Task<AuthenticationResult> AuthenticateAsync(string accountName = null, AuthenticationMode mode = AuthenticationMode.Interactive)
        {
            using CancellationTokenSource cts = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            AuthenticationResult result;
            var accounts = await _app.GetAccountsAsync();
            IAccount account;
            if (string.IsNullOrWhiteSpace(accountName))
                account = accounts.FirstOrDefault();
            else
                account = accounts.Where(x => string.Compare(x.Username, accountName, true) == 0).FirstOrDefault();
                                                                                                      
            try
            {
                result = await _app.AcquireTokenSilent(_scopes, account)
                                  .ExecuteAsync(cts.Token);
            }
            catch (MsalUiRequiredException)
            {
                switch(mode)
                {
                    case AuthenticationMode.Interactive:
                        result = await _app.AcquireTokenInteractive(_scopes).ExecuteAsync(cts.Token);
                        break;
                    case AuthenticationMode.DeviceCode:
                        result = await _app.AcquireTokenWithDeviceCode(_scopes, callback =>
                        {
                            Console.WriteLine(callback.Message);
                            return Task.FromResult(0);
                        }).ExecuteAsync(cts.Token);
                        break;
                    default:
                        throw new ArgumentException($"Unsupported authentication mode: {mode}");
                }
            }
            
            return result;
        }
    }
}
