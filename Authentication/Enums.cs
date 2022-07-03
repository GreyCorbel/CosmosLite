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
    /// <summary>
    /// Public client supported authentication flows
    /// </summary>
    public enum AuthenticationMode
    {
        /// <summary>
        /// Interactive flow with webview or browser
        /// </summary>
        Interactive,
        /// <summary>
        /// DeviceCode flow with authentication performed with code on different device
        /// </summary>
        DeviceCode,
    }

    /// <summary>
    /// Type of client we use for auth
    /// </summary>
    enum AuthenticationFlow
    {
        PublicClient,
        ConfidentialClient,
        ManagedIdentity,
        UserAssignedIdentity
    }
}