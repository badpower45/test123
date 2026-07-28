import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Create Supabase client
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Get the payload from the webhook (INSERT on pulses)
        const payload = await req.json()
        const newPulse = payload.record

        // Only process if inside_geofence is false
        if (newPulse.inside_geofence === false) {
            console.log(`Processing violation for pulse: ${newPulse.id}, attendance: ${newPulse.attendance_id}`)

            // Fetch the last 2 pulses for this attendance (excluding the current one if it's already inserted, 
            // but usually webhooks fire after insert. So we want the last 3 total including this one).
            // Actually, let's just fetch the last 3 pulses ordered by timestamp desc.
            const { data: lastPulses, error: pulsesError } = await supabaseClient
                .from('pulses')
                .select('inside_geofence, timestamp')
                .eq('attendance_id', newPulse.attendance_id)
                .order('timestamp', { ascending: false })
                .limit(3)

            if (pulsesError) {
                throw pulsesError
            }

            // Check if we have 3 pulses and all are violations
            if (lastPulses && lastPulses.length === 3) {
                const allViolations = lastPulses.every(p => p.inside_geofence === false)

                if (allViolations) {
                    console.log(`3rd Violation detected for attendance: ${newPulse.attendance_id}. Auto-checkout disabled by policy.`)

                    // Policy: no automatic check-out from edge functions.
                    // Keep a warning notification only.
                    const { error: notifError } = await supabaseClient
                        .from('notifications')
                        .insert({
                            employee_id: newPulse.employee_id,
                            title: 'تحذير خروج من النطاق',
                            body: 'تم رصد 3 مخالفات متتالية خارج النطاق. لا يوجد انصراف تلقائي من النظام.',
                            type: 'geofence_warning',
                            is_read: false,
                            created_at: new Date().toISOString()
                        })

                    if (notifError) {
                        console.error('Error sending warning notification:', notifError)
                    }
                }
            }
        }

        return new Response(JSON.stringify({ message: 'Pulse processed' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error('Error processing pulse:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})
