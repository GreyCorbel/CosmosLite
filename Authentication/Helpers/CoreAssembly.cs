using System;
using System.Reflection;

namespace GreyCorbel.Identity.Authentication
{
    static class CoreAssembly
    {
        public static readonly Assembly Reference = typeof(CoreAssembly).Assembly;
        public static readonly Version Version = Reference.GetName().Version;
    }
}
