export GraphPlot, graphplot, graphplot!

"""
    graphplot(graph::AbstractGraph)
    graphplot!(ax, graph::AbstractGraph)

Creates a plot of the network `graph`. Consists of multiple steps:
- Layout the nodes: the `layout` attribute is has to be a function `f(adj_matrix)::pos`
  where `pos` is either an array of `Point2f0` or `(x, y)` tuples
- plot edges as `linesegments`-plot
- plot nodes as `scatter`-plot
- if `nlabels!=nothing` plot node labels as `text`-plot
- if `elabels!=nothing` plot edge labels as `text`-plot

The main attributes for the subplots are exposed as attributes for `graphplot`.
Additional attributes for the `scatter`, `linesegments` and `text` plots can be provided
as a named tuples to `node_attr`, `edge_attr`, `nlabels_attr` and `elabels_attr`.

Most of the arguments can be either given as a vector of length of the
edges/nodes or as a single value. One might run into errors when changing the
underlying graph and therefore changing the number of Edges/Nodes.

## Attributes
### Main attributes
- `layout`: function `adj_matrix->Vector{Point}` determines the base layout
- `node_color=scatter_theme.color`
- `node_size=scatter_theme.markersize`
- `node_marker=scatter_theme.marker`k
- `node_attr=(;)`: List of kw arguments which gets passed to the `scatter` command
- `edge_color=lineseg_theme.color`: Pass a vector with 2 colors per edge to get
  color gradients.
- `edge_width=lineseg_theme.linewidth`: Pass a vector with 2 width per edge to
  get pointy edges.
- `edge_attr=(;)`: List of kw arguments which gets passed to the `linesegments` command

### Node labels
The position of each label is determined by the node position plus an offset in
data space.

- `nlabels=nothing`: `Vector{String}` with label for each node
- `nlabels_align=(:left, :bottom)`: Anchor of text field.
- `nlabels_color=labels_theme.color`
- `nlabels_offset=nothing`: `Point` or `Vector{Point}`
- `nlabels_textsize=labels_theme.textsize`
- `nlabels_attr=(;)`: List of kw arguments which gets passed to the `text` command

### Edge labels
The base position of each label is determinded by `src + shift*(dst-src)`. The
additional `distance` parameter is given in pixels and shifts the text away from
the edge.

- `elabels=nothing`: `Vector{String}` with label for each edge
- `elabels_align=(:center, :bottom)`: Anchor of text field.
- `elabels_distance=0.0`: Pixel distance of anchor to edge.
- `elabels_shift=0.5`: Position between src and dst of edge.
- `elabels_opposite=Int[]`: List of edge indices, for which the label should be
  displayed on the opposite side
- `elabels_rotation=nothing`: Angle of text per label. If `nothing` this will be
  determined by the edge angle!
- `elabels_offset=nothing`: Additional offset in data space
- `elabels_color=labels_theme.color`
- `elabels_textsize=labels_theme.textsize`
- `elabels_attr=(;)`: List of kw arguments which gets passed to the `text` command

"""
@recipe(GraphPlot, graph) do scene
    # TODO: figure out this whole theme business
    scatter_theme = default_theme(scene, Scatter)
    lineseg_theme = default_theme(scene, LineSegments)
    labels_theme = default_theme(scene, Makie.Text)
    Attributes(
        layout = NetworkLayout.Spring.layout,
        # node attributes (Scatter)
        node_color = scatter_theme.color,
        node_size = scatter_theme.markersize,
        node_marker = scatter_theme.marker,
        node_attr = (;),
        # edge attributes (LineSegements)
        edge_color = lineseg_theme.color,
        edge_width = lineseg_theme.linewidth,
        edge_attr = (;),
        # node label attributes (Text)
        nlabels = nothing,
        nlabels_align = (:left, :bottom),
        nlabels_color = labels_theme.color,
        nlabels_offset = nothing,
        nlabels_textsize = labels_theme.textsize,
        nlabels_attr = (;),
        # edge label attributes (Text)
        elabels = nothing,
        elabels_align = (:center, :bottom),
        elabels_color = labels_theme.color,
        elabels_distance = 0.0,
        elabels_shift = 0.5,
        elabels_offset = nothing,
        elabels_rotation = nothing,
        elabels_opposite = Int[],
        elabels_textsize = labels_theme.textsize,
        elabels_attr = (;),
    )
end

function Makie.plot!(gp::GraphPlot)
    graph = gp[:graph]

    # create initial vertex positions, will be updated on changes to graph or layout
    # make node_position-Observable available as named attribute from the outside
    gp[:node_positions] = @lift begin
        A = adjacency_matrix($graph)
        [Point(p) for p in ($(gp.layout))(A)]
    end

    node_positions = gp[:node_positions]

    # create views into the node_positions, will be updated node_position changes
    # in case of a graph change the node_position will change anyway
    edge_segments = @lift begin
        indices = vec([getfield(e, s) for s in (:src, :dst), e in edges(graph[])])
        ($node_positions)[indices]
    end

    # in case the edge_with is same as the number of edges
    # create a new observable which doubles the values for compat with line segments
    if length(gp.edge_width[]) == ne(graph[])
        lineseg_width = @lift repeat($(gp.edge_width), inner=2)
    else
        lineseg_width = gp.edge_width
    end

    # plot edges
    edge_plot = linesegments!(gp, edge_segments;
                              color=gp.edge_color,
                              linewidth=lineseg_width,
                              gp.edge_attr...)

    # plot vertices
    vertex_plot = scatter!(gp, node_positions;
                           color=gp.node_color,
                           marker=gp.node_marker,
                           markersize=gp.node_size,
                           gp.node_attr...)

    # plot node labels
    if gp.nlabels[] !== nothing
        positions = @lift begin
            if $(gp.nlabels_offset) != nothing
                $node_positions .+ $(gp.nlabels_offset)
            else
                copy($node_positions)
            end
        end
        nlabels_plot = text!(gp, gp.nlabels;
                             position=positions,
                             align=gp.nlabels_align,
                             color=gp.nlabels_color,
                             textsize=gp.nlabels_textsize,
                             gp.nlabels_attr...)
    end

    # plot edge labels
    if gp.elabels[] !== nothing
        sc = Makie.parent_scene(gp)
        # calculate the vectors for each edge
        edge_vec_px = lift(edge_segments, graph, sc.px_area, sc.camera.projectionview) do seg, g, pxa, pv
            # project should transform to 2d point in px space
            [project(sc, seg[2i]) - project(sc, seg[2i-1]) for i in 1:ne(g)]
            # [seg[2i] - seg[2i-1] for i in 1:ne(g)]
        end

        # rotations based on the edge_vec_px and opposite argument
        rotations = @lift begin
            if $(gp.elabels_rotation) isa Real
                # fix rotation to a signle angle
                rot = [$(gp.elabels_rotation) for i in 1:ne($graph)]
            else
                # determine rotation by edge vector
                rot = map(v -> atan(v.data[2], v.data[1]), $edge_vec_px)
                for i in $(gp.elabels_opposite)
                    rot[i] += π
                end
                # if there are user provided rotations for some labels, use those
                if $(gp.elabels_rotation) isa Vector
                    for (i, α) in enumerate($(gp.elabels_rotation))
                        α !== nothing && (rot[i] = α)
                    end
                end
            end
            return rot
        end

        # positions: center point between nodes + offset + distance*normal + shift*edge direction
        positions = @lift begin
            # do the same for nodes...
            pos = [$edge_segments[2i-1] for i in 1:ne($graph)]
            dst = [$edge_segments[2i]   for i in 1:ne($graph)]

            pos .= pos .+ $(gp.elabels_shift) .* (dst .- pos)

            if $(gp.elabels_offset) !== nothing
                pos .= pos .+ $(gp.elabels_offset)
            end
            pos
        end

        # calculate the offset in pixels in normal direction to the edge
        offsets = @lift begin
            offsets = map(p -> Point(-p.data[2], p.data[1])/norm(p), $edge_vec_px)
            offsets .= $(gp.elabels_distance) .* offsets
        end

        elabels_plot = text!(gp, gp.elabels;
                             position=positions,
                             rotation=rotations,
                             offset=offsets,
                             align=gp.elabels_align,
                             color=gp.elabels_color,
                             textsize=gp.elabels_textsize,
                             gp.elabels_attr...)
    end

    return gp
end
