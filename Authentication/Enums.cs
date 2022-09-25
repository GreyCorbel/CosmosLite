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
        /// <summary>
        /// Windows Integrated Authentication - supported on machines joined to AD, or hybrid joined
        /// </summary>
        WIA,
    }

    /// <summary>
    /// Type of client we use for auth
    /// </summary>
    enum AuthenticationFlow
    {
        PublicClient,
        PublicClientWithDeviceCode,
        PublicClientWithWia,
        ConfidentialClient,
        ManagedIdentity,
        UserAssignedIdentity,
        ResourceOwnerPassword
    }
}