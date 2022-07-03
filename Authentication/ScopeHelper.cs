using System;
using System.Collections.Generic;
using System.Text;

namespace GreyCorbel.Identity.Authentication
{
    internal static class ScopeHelper
    {
        static readonly string defaultScope = "/.default";
        public static string ScopeToResource(string[] scopes)
        {
            if(null==scopes) throw new ArgumentNullException(nameof(scopes));
            if (scopes.Length == 0) throw new ArgumentException("No scopes provided");
            if (scopes[0].EndsWith(defaultScope, StringComparison.Ordinal))
                return scopes[0].Replace(defaultScope, "");
            
            return scopes[0];
        }

        public static string[] ResourceToScope(string resource)
        {
            if (null == resource) throw new ArgumentNullException(nameof(resource));
            if (resource.Length == 0) throw new ArgumentException("No resource provided");
            if (resource.EndsWith(defaultScope, StringComparison.Ordinal))
                return new string[] { resource };

            return new string[] { $"{resource}{defaultScope}" };
        }
    }
}
