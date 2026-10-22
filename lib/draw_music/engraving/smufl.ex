defmodule DrawMusic.Engraving.Smufl do
  @moduledoc """
  The SMuFL glyphs we draw with, from the vendored Bravura metadata
  (`priv/smufl`, Bravura 1.482). Everything is read at compile time; a glyph
  missing from the metadata fails the build.

  Glyph metrics are in staff spaces, with y pointing up as in SMuFL.
  """

  @glyphnames_path Path.expand("../../../priv/smufl/glyphnames.json", __DIR__)
  @metadata_path Path.expand("../../../priv/smufl/Bravura.json", __DIR__)
  @external_resource @glyphnames_path
  @external_resource @metadata_path

  @glyphs ~w(
    gClef fClef brace
    noteheadWhole noteheadHalf noteheadBlack augmentationDot
    flag8thUp flag8thDown flag16thUp flag16thDown
    flag32ndUp flag32ndDown flag64thUp flag64thDown
    restWhole restHalf restQuarter rest8th rest16th rest32nd rest64th
    accidentalDoubleFlat accidentalFlat accidentalNatural accidentalSharp accidentalDoubleSharp
    timeSig0 timeSig1 timeSig2 timeSig3 timeSig4 timeSig5 timeSig6 timeSig7 timeSig8 timeSig9
    timeSigCommon timeSigCutCommon
    noteWhole noteHalfUp noteQuarterUp note8thUp note16thUp note32ndUp note64thUp
  )a

  glyphnames = @glyphnames_path |> File.read!() |> JSON.decode!()
  metadata = @metadata_path |> File.read!() |> JSON.decode!()

  @chars Map.new(@glyphs, fn glyph ->
           %{"codepoint" => "U+" <> hex} = Map.fetch!(glyphnames, Atom.to_string(glyph))
           {glyph, <<String.to_integer(hex, 16)::utf8>>}
         end)

  @bboxes Map.new(@glyphs, fn glyph ->
            %{"bBoxSW" => [x0, y0], "bBoxNE" => [x1, y1]} =
              Map.fetch!(metadata["glyphBBoxes"], Atom.to_string(glyph))

            {glyph, {x0, y0, x1, y1}}
          end)

  @anchors for glyph <- @glyphs,
               {name, [x, y]} <- metadata["glyphsWithAnchors"][Atom.to_string(glyph)] || %{},
               into: %{},
               do: {{glyph, name}, {x, y}}

  @defaults metadata["engravingDefaults"]

  @doc "The glyphs available."
  def glyphs, do: @glyphs

  @doc "The character that draws `glyph` in Bravura."
  def char(glyph), do: Map.fetch!(@chars, glyph)

  @doc "Bounding box `{x0, y0, x1, y1}` of `glyph` (SW corner, NE corner)."
  def bbox(glyph), do: Map.fetch!(@bboxes, glyph)

  @doc "Width of `glyph`."
  def width(glyph) do
    {x0, _y0, x1, _y1} = bbox(glyph)
    x1 - x0
  end

  @doc "A named anchor of `glyph`, such as `\"stemUpSE\"`, as `{x, y}`; nil if it has none."
  def anchor(glyph, name), do: Map.get(@anchors, {glyph, name})

  @doc "An engraving default, such as `\"staffLineThickness\"`."
  def default(name) when is_binary(name), do: Map.fetch!(@defaults, name)
end
