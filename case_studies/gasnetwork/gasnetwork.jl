using Plasmo
using JLD2

#Model Data
#NOTE: nx defined in calling file
horizon = 24*3600   #the time horizon is in seconds
nt = 24              #number of time points
dt = horizon / (nt - 1) #time delta
#nx = 10

include((@__DIR__)*"/modelfunctions.jl")
include((@__DIR__)*"/load_data.jl")

function create_gas_network_problem()
    gas_network = OptiGraph()
    for pipe in pipelines
        add_subgraph!(gas_network,pipe)
    end
    for compressor in compressors
        add_subgraph!(gas_network,compressor)
    end
    for junction in junctions
        add_subgraph!(gas_network,junction)
    end

    for pipe in pipelines
        junction_from,junction_to = pipe_map[pipe]
        @linkconstraint(gas_network,[t = 1:nt],pipe[:pin][t] == junction_from[:time_nodes][t][:pressure])
        @linkconstraint(gas_network,[t = 1:nt],pipe[:pout][t] == junction_to[:time_nodes][t][:pressure])
    end

    for compressor in compressors
        junction_from,junction_to = compressor_map[compressor]
        nodes = compressor[:time_nodes]
        @linkconstraint(gas_network,[t = 1:nt],nodes[t][:psuction] == junction_from[:time_nodes][t][:pressure])
        @linkconstraint(gas_network,[t = 1:nt],nodes[t][:pdischarge]  == junction_to[:time_nodes][t][:pressure])
    end

    for junction in junctions
        devices_in = junction_map_in[junction]
        devices_out = junction_map_out[junction]

        if length(devices_in) > 0
            flow_in = [sum(devices_in[i][:fout][t] for i = 1:length(devices_in)) for t = 1:nt]
        else
            flow_in = zeros(nt)
        end
        if length(devices_out) > 0
            flow_out = [sum(devices_out[i][:fin][t] for i = 1:length(devices_out)) for t = 1:nt]
        else
            flow_out = zeros(nt)
        end
        total_supplied = [junction[:time_nodes][t][:total_supplied] for t = 1:nt]
        total_delivered = [junction[:time_nodes][t][:total_delivered] for t = 1:nt]

        @linkconstraint(gas_network,[t = 1:nt], flow_in[t] - flow_out[t] + total_supplied[t] - total_delivered[t] == 0)
    end


    #Fix Demands
    for (i,j_data) in junction_data
        jmodel = jmap[i]
        dvalues = j_data[:demand_values]
        n_demands = length(dvalues)
        nodes = jmodel[:time_nodes]
        for (t,node) in enumerate(nodes)
            @constraint(node,[d = 1:n_demands],node[:fdemand][d] == dvalues[d][t])
        end
    end
    return gas_network
end
