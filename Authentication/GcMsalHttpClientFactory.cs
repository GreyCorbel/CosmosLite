using Microsoft.Identity.Client;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;

namespace GreyCorbel.Identity.Authentication
{
    internal class GcMsalHttpClientFactory : IMsalHttpClientFactory
    {
        static HttpClient httpClient;

        public GcMsalHttpClientFactory()
        {
            if (null == httpClient)
            {
                httpClient = new HttpClient();
                httpClient.DefaultRequestHeaders.UserAgent.Add(new System.Net.Http.Headers.ProductInfoHeaderValue("AadAuthenticationFactory", CoreAssembly.Version.ToString()));
            }
        }
        public HttpClient GetHttpClient()
        {
            return httpClient;
        }
    }
}
