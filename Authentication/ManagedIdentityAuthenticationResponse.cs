﻿using System;
using System.Collections.Generic;
using System.Text;

namespace GreyCorbel.Identity.Authentication
{
    internal class ManagedIdentityAuthenticationResponse
    {
        public string access_token { get; set; }
        public long expires_on { get; set; }
        public string resource { get; set; }
        public string token_type { get; set; }
        public string client_id { get; set; }
    }
}
