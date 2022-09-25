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
    class ManagedIdentityClientApplication:TokenProvider
#pragma warning restore CA1001

    {
        ITokenProvider _tokenProvider = null;
        AuthenticationResult _cachedToken = null;
        private readonly SemaphoreSlim _lock = new SemaphoreSlim(1, 1);


        public ManagedIdentityClientApplication(IMsalHttpClientFactory factory, string clientId = null)
        :base(factory, clientId)
        {
            if (!string.IsNullOrEmpty(IdentityEndpoint) && !string.IsNullOrEmpty(IdentityHeader))
                _tokenProvider = new AppServiceTokenProvider(factory, clientId);
            //else if (!string.IsNullOrEmpty(IdentityEndpoint) && !string.IsNullOrEmpty(ImdsEndpoint))
            //    _specialization = ManagedIdentityClientApplicationSpecialization.Arc;
            else
                _tokenProvider = new VMIdentityTokenProvider(factory, clientId);
        }

        public override async Task<AuthenticationResult> AcquireTokenForClientAsync(string[] scopes, CancellationToken cancellationToken)
        {
            await _lock.WaitAsync().ConfigureAwait(false);

            try
            {
                if (null == _cachedToken || _cachedToken.ExpiresOn.UtcDateTime < DateTime.UtcNow.AddSeconds(-_ticketOverlapSeconds))
                {
                    if (null != _tokenProvider)
                    {
                        _cachedToken = await _tokenProvider.AcquireTokenForClientAsync(scopes, cancellationToken).ConfigureAwait(false);
                    }
                    else
                        throw new InvalidOperationException("Token provider not initialized");
                }
                return _cachedToken;
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
