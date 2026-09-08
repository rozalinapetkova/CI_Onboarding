<?xml version="1.0" encoding="UTF-8"?>
<!--
  Reference enrichment stylesheet for the Day 2.2 lab.
  Drop this into the iFlow Resources as xslt_<initials>_EnrichCanonicalOrder.xsl.
-->
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:exf="http://sap.com/it/"
                xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <xsl:output method="xml" indent="yes"/>

  <!-- Identity transform — copy everything by default. -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Root: set the routingHint header as a side effect, then continue normally. -->
  <xsl:template match="/CanonicalOrder">
    <xsl:variable name="hint"
                  select="if (header/priority='HIGH') then 'expedited' else 'standard'"/>
    <xsl:value-of select="exf:setHeader('routingHint', $hint)"/>
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Header: append <routingHint> and <receivedAt>. -->
  <xsl:template match="CanonicalOrder/header">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <routingHint>
        <xsl:value-of select="if (priority='HIGH') then 'expedited' else 'standard'"/>
      </routingHint>
      <receivedAt>
        <xsl:value-of select="format-dateTime(current-dateTime(),
                              '[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01]Z')"/>
      </receivedAt>
    </xsl:copy>
  </xsl:template>

  <!-- Currency: normalize to upper-case; default to 'EUR' if blank. -->
  <xsl:template match="header/currencyIso4217">
    <xsl:copy>
      <xsl:choose>
        <xsl:when test="normalize-space(.)=''">
          <xsl:text>EUR</xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="upper-case(normalize-space(.))"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:copy>
  </xsl:template>

  <!-- After <lines>, emit a <grouped> sibling with lines grouped by SKU prefix. -->
  <xsl:template match="CanonicalOrder/lines">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
    <grouped>
      <xsl:for-each-group select="line" group-by="substring(sku,1,1)">
        <group prefix="{current-grouping-key()}">
          <xsl:for-each select="current-group()">
            <sku><xsl:value-of select="sku"/></sku>
          </xsl:for-each>
        </group>
      </xsl:for-each-group>
    </grouped>
  </xsl:template>

</xsl:stylesheet>
