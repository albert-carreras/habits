import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json",
};

const userDataTables = [
  "habit_completions",
  "habits",
  "things",
];

Deno.serve(async (request) => {
  if (request.method !== "DELETE") {
    return json({ error: "Method not allowed" }, 405);
  }

  const token = bearerToken(request.headers.get("Authorization"));
  if (!token) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "Server is not configured for account deletion." }, 500);
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  const userID = userData.user?.id;

  if (userError || !userID) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    for (const table of userDataTables) {
      const { error } = await supabase.from(table).delete().eq("user_id", userID);
      if (error) {
        throw new Error(`Failed deleting ${table}: ${error.message}`);
      }
    }

    const { error: deleteUserError } = await supabase.auth.admin.deleteUser(userID);
    if (deleteUserError) {
      throw deleteUserError;
    }

    return json({ deleted: true }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Account deletion failed.";
    return json({ error: message }, 500);
  }
});

function bearerToken(header: string | null): string | null {
  if (!header) {
    return null;
  }

  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }

  return token;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
