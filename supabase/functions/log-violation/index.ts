import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const body = await req.json()
    const employee_id = body.employee_id
    const branch_id = body.branch_id
    // Accept both legacy and new keys from client
    const distance_from_center = body.distance_from_center ?? body.distance
    const radius_meters = body.radius_meters ?? body.geofence_radius
    const timestamp = body.timestamp
    const latitude = body.latitude
    const longitude = body.longitude

    // Insert violation using service role key (bypasses RLS)
    const { error } = await supabase
      .from('geofence_violations')
      .insert({
        employee_id,
        branch_id,
        distance_from_center,
        radius_meters,
        timestamp: timestamp || new Date().toISOString(),
        latitude,
        longitude,
      })

    if (error) throw error

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
