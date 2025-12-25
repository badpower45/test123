// Edge Function: session-validation-action
// Approve or reject session validation requests
// Creates TRUE or FALSE pulses based on manager decision

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      }
    );

    const { request_id, action, manager_notes } = await req.json();

    // Validate input
    if (!request_id || !action) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing required fields: request_id, action",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    if (!["approve", "reject"].includes(action)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid action. Must be 'approve' or 'reject'",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    console.log(`Processing session validation: ${request_id}, action: ${action}`);

    // Get request details
    const { data: request, error: requestError } = await supabaseClient
      .from("session_validation_requests")
      .select("*")
      .eq("id", request_id)
      .single();

    if (requestError || !request) {
      console.error("Request not found:", requestError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Session validation request not found",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 404,
        }
      );
    }

    // Check if already processed
    if (request.status !== "pending") {
      return new Response(
        JSON.stringify({
          success: false,
          error: `Request already ${request.status}`,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    // Create pulses for the gap
    const insideGeofence = action === "approve";
    const pulses = [];
    const startTime = new Date(request.gap_start_time);
    const endTime = new Date(request.gap_end_time);

    let currentTime = new Date(startTime.getTime() + 5 * 60 * 1000); // +5 minutes

    while (currentTime < endTime) {
      pulses.push({
        employee_id: request.employee_id,
        attendance_id: request.attendance_id,
        branch_id: request.branch_id,
        timestamp: currentTime.toISOString(),
        inside_geofence: insideGeofence,
        is_within_geofence: insideGeofence,
        distance_from_center: 0.0,
        validated_by_wifi: false,
        validated_by_location: false,
        created_by_validation: true,
        validation_request_id: request_id,
      });

      currentTime = new Date(currentTime.getTime() + 5 * 60 * 1000); // +5 minutes
    }

    // Insert pulses
    if (pulses.length > 0) {
      const { error: pulsesError } = await supabaseClient
        .from("location_pulses")
        .insert(pulses);

      if (pulsesError) {
        console.error("Error creating pulses:", pulsesError);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to create pulses",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
          }
        );
      }

      console.log(`Created ${pulses.length} ${insideGeofence ? "TRUE" : "FALSE"} pulses`);
    }

    // Update request status
    const { error: updateError } = await supabaseClient
      .from("session_validation_requests")
      .update({
        status: action === "approve" ? "approved" : "rejected",
        manager_response_time: new Date().toISOString(),
        manager_notes: manager_notes || null,
      })
      .eq("id", request_id);

    if (updateError) {
      console.error("Error updating request:", updateError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to update request status",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        }
      );
    }

    // If approved, update attendance check_in_time
    if (action === "approve" && request.attendance_id) {
      const { error: attendanceError } = await supabaseClient
        .from("attendance")
        .update({
          check_in_time: request.gap_start_time,
        })
        .eq("id", request.attendance_id);

      if (attendanceError) {
        console.error("Error updating attendance:", attendanceError);
        // Don't fail the whole operation
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        action: action,
        pulses_created: pulses.length,
        message: `Session validation ${action === "approve" ? "approved" : "rejected"} successfully`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
